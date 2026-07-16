#if UNITY_EDITOR

using System.IO;
using UnityEditor.PackageManager;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    internal static class BuildCommitWorkflowSyncUtility
    {
        internal const string TemplateRelativePath = "WorkflowTemplates/buildcommit-auto-build.yml";
        internal const string WorkflowRelativePath = ".github/workflows/buildcommit-auto-build.yml";
        internal const string AndroidBuildActionRelativePath = ".github/actions/build-android/action.yml";
        internal const string IosBuildActionRelativePath = ".github/actions/build-ios/action.yml";
        internal const string AllocateRunnerScriptRelativePath = ".github/scripts/allocate-unity-mobile-runner.js";
        internal const string ValidateSecretsScriptRelativePath = ".github/scripts/validate-local-runner-secrets.sh";
        internal const string ResolveUnityProjectScriptRelativePath = ".github/scripts/resolve-unity-project.sh";
        internal const string ResolveUnityScriptRelativePath = ".github/scripts/resolve-unity-editor.sh";
        internal const string EnsureUnityModulesScriptRelativePath = ".github/scripts/ensure-unity-editor-modules.sh";
        internal const string PreparePrivatePackageAccessScriptRelativePath = ".github/scripts/prepare-actionfit-private-package-access.sh";
        internal const string ResolveLocalSecretRootScriptRelativePath = ".github/scripts/resolve-local-secret-root.sh";
        internal const string NotifySlackScriptRelativePath = ".github/scripts/notify-slack-build-result.sh";
        internal const string CleanupOldBuildArtifactsScriptRelativePath = ".github/scripts/cleanup-old-build-artifacts.sh";
        internal const string StoreUploadWorkerScriptRelativePath = ".github/scripts/store-upload-worker.rb";
        internal const string UploadGooglePlayScriptRelativePath = ".github/scripts/upload-google-play.sh";
        internal const string UploadTestFlightScriptRelativePath = ".github/scripts/upload-testflight.rb";
        internal const string CheckTestFlightBuildNumberScriptRelativePath = ".github/scripts/check-testflight-build-number.rb";
        internal const string UploadSlackFileScriptRelativePath = ".github/scripts/upload-slack-file.sh";
        internal const string ManageSlackApkDeliveryReceiptScriptRelativePath = ".github/scripts/manage-slack-apk-delivery-receipt.rb";

        private const string PackageName = "com.actionfit.buildautomation";
        private static readonly string[] PackageAssetRelativePaths =
        {
            TemplateRelativePath,
            AndroidBuildActionRelativePath,
            IosBuildActionRelativePath,
            AllocateRunnerScriptRelativePath,
            ValidateSecretsScriptRelativePath,
            ResolveUnityProjectScriptRelativePath,
            ResolveUnityScriptRelativePath,
            EnsureUnityModulesScriptRelativePath,
            PreparePrivatePackageAccessScriptRelativePath,
            ResolveLocalSecretRootScriptRelativePath,
            NotifySlackScriptRelativePath,
            CleanupOldBuildArtifactsScriptRelativePath,
            StoreUploadWorkerScriptRelativePath,
            UploadGooglePlayScriptRelativePath,
            UploadTestFlightScriptRelativePath,
            CheckTestFlightBuildNumberScriptRelativePath,
            UploadSlackFileScriptRelativePath,
            ManageSlackApkDeliveryReceiptScriptRelativePath
        };

        private static readonly string[] ProjectAssetRelativePaths =
        {
            WorkflowRelativePath,
            AndroidBuildActionRelativePath,
            IosBuildActionRelativePath,
            AllocateRunnerScriptRelativePath,
            ValidateSecretsScriptRelativePath,
            ResolveUnityProjectScriptRelativePath,
            ResolveUnityScriptRelativePath,
            EnsureUnityModulesScriptRelativePath,
            PreparePrivatePackageAccessScriptRelativePath,
            ResolveLocalSecretRootScriptRelativePath,
            NotifySlackScriptRelativePath,
            CleanupOldBuildArtifactsScriptRelativePath,
            StoreUploadWorkerScriptRelativePath,
            UploadGooglePlayScriptRelativePath,
            UploadTestFlightScriptRelativePath,
            CheckTestFlightBuildNumberScriptRelativePath,
            UploadSlackFileScriptRelativePath,
            ManageSlackApkDeliveryReceiptScriptRelativePath
        };

        private static readonly string[] ObsoleteProjectAssetRelativePaths =
        {
            ".github/workflows/buildcommit-slack-delivery.yml"
        };

        internal static bool IsWorkflowCurrent()
        {
            for (int i = 0; i < PackageAssetRelativePaths.Length; i++)
            {
                if (!PackageFileMatchesProjectFile(PackageAssetRelativePaths[i], ProjectAssetRelativePaths[i]))
                    return false;
            }

            foreach (string relativePath in ObsoleteProjectAssetRelativePaths)
            {
                if (File.Exists(GetProjectPath(relativePath)))
                    return false;
            }

            return true;
        }

        internal static bool WorkflowExists()
        {
            return File.Exists(GetProjectPath(WorkflowRelativePath));
        }

        internal static string GetStatusMessage()
        {
            if (!BuildRequestUtility.TryGetRepositoryRoot(out string repositoryRoot, out string repositoryError))
                return repositoryError;

            for (int i = 0; i < PackageAssetRelativePaths.Length; i++)
            {
                string packagePath = GetPackagePath(PackageAssetRelativePaths[i]);
                if (string.IsNullOrEmpty(packagePath) || !File.Exists(packagePath))
                    return $"Template missing: {PackageAssetRelativePaths[i]}";
            }

            for (int i = 0; i < ProjectAssetRelativePaths.Length; i++)
            {
                string projectPath = GetProjectPath(ProjectAssetRelativePaths[i]);
                if (!File.Exists(projectPath))
                    return $"Repository workflow asset missing: {ProjectAssetRelativePaths[i]} ({repositoryRoot})";
            }

            return IsWorkflowCurrent()
                ? $"Workflow assets are up to date: {GetWorkflowAssetSummary()}"
                : $"Workflow assets differ from package templates: {GetWorkflowAssetSummary()}";
        }

        internal static bool TrySync(out string message)
        {
            message = "";

            if (!BuildRequestUtility.TryGetRepositoryRoot(out _, out string repositoryError))
            {
                message = repositoryError;
                return false;
            }

            for (int i = 0; i < PackageAssetRelativePaths.Length; i++)
            {
                if (!TrySyncPackageFile(PackageAssetRelativePaths[i], ProjectAssetRelativePaths[i], out string assetMessage))
                {
                    message = assetMessage;
                    return false;
                }

                if (!string.IsNullOrEmpty(message))
                    message += "; ";
                message += assetMessage;
            }

            int removedObsoleteAssets = RemoveObsoleteRepositoryAssets();
            if (removedObsoleteAssets > 0)
                message += $"; Removed {removedObsoleteAssets} obsolete repository delivery workflow(s)";

            int removedLegacyAssets = RemoveLegacyUnityProjectAssets();
            if (removedLegacyAssets > 0)
                message += $"; Removed {removedLegacyAssets} legacy Unity-project workflow asset(s)";

            return true;
        }

        internal static string GetWorkflowAssetSummary()
        {
            return $"{WorkflowRelativePath}, {AndroidBuildActionRelativePath}, {IosBuildActionRelativePath}, {AllocateRunnerScriptRelativePath}, {ValidateSecretsScriptRelativePath}, {ResolveUnityProjectScriptRelativePath}, {EnsureUnityModulesScriptRelativePath}, {PreparePrivatePackageAccessScriptRelativePath}, {ResolveLocalSecretRootScriptRelativePath}, {NotifySlackScriptRelativePath}, {CleanupOldBuildArtifactsScriptRelativePath}, {StoreUploadWorkerScriptRelativePath}, {UploadGooglePlayScriptRelativePath}, {UploadTestFlightScriptRelativePath}, {CheckTestFlightBuildNumberScriptRelativePath}, {UploadSlackFileScriptRelativePath}, {ManageSlackApkDeliveryReceiptScriptRelativePath}";
        }

        private static bool PackageFileMatchesProjectFile(string packageRelativePath, string projectRelativePath)
        {
            string packagePath = GetPackagePath(packageRelativePath);
            string projectPath = GetProjectPath(projectRelativePath);

            return !string.IsNullOrEmpty(packagePath) &&
                   File.Exists(packagePath) &&
                   File.Exists(projectPath) &&
                   FilesMatch(packagePath, projectPath);
        }

        private static bool TrySyncPackageFile(string packageRelativePath, string projectRelativePath, out string message)
        {
            string packagePath = GetPackagePath(packageRelativePath);
            if (string.IsNullOrEmpty(packagePath) || !File.Exists(packagePath))
            {
                message = $"Template not found: {packageRelativePath}";
                return false;
            }

            string projectPath = GetProjectPath(projectRelativePath);
            if (string.IsNullOrEmpty(projectPath))
            {
                message = $"Git repository path could not be resolved for: {projectRelativePath}";
                return false;
            }

            string projectDirectory = Path.GetDirectoryName(projectPath);
            if (!string.IsNullOrEmpty(projectDirectory))
                Directory.CreateDirectory(projectDirectory);

            if (File.Exists(projectPath) && FilesMatch(packagePath, projectPath))
            {
                message = $"Already up to date: {projectRelativePath}";
                return true;
            }

            File.Copy(packagePath, projectPath, true);
            message = $"Updated {projectRelativePath} from {packageRelativePath}";
            return true;
        }

        private static string GetPackagePath(string relativePath)
        {
            string packageRoot = GetPackageRoot();
            return string.IsNullOrEmpty(packageRoot)
                ? null
                : CombineRootPath(packageRoot, relativePath);
        }

        private static string GetProjectPath(string relativePath)
        {
            string repositoryRoot = GetRepositoryRoot();
            return string.IsNullOrEmpty(repositoryRoot)
                ? null
                : CombineRootPath(repositoryRoot, relativePath);
        }

        private static string GetPackageRoot()
        {
            PackageInfo packageInfo = PackageInfo.FindForAssembly(typeof(BuildCommitWorkflowSyncUtility).Assembly);
            if (packageInfo != null && !string.IsNullOrEmpty(packageInfo.resolvedPath))
                return Path.GetFullPath(packageInfo.resolvedPath);

            string embeddedPath = Path.GetFullPath(Path.Combine(GetUnityProjectRoot(), "Packages", PackageName));
            return Directory.Exists(embeddedPath) ? embeddedPath : null;
        }

        private static string GetUnityProjectRoot()
        {
            return Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        }

        private static string GetRepositoryRoot()
        {
            return BuildRequestUtility.TryGetRepositoryRoot(out string repositoryRoot, out _)
                ? repositoryRoot
                : null;
        }

        private static int RemoveLegacyUnityProjectAssets()
        {
            string unityProjectRoot = GetUnityProjectRoot();
            string repositoryRoot = GetRepositoryRoot();
            if (string.IsNullOrEmpty(repositoryRoot) ||
                string.Equals(unityProjectRoot, repositoryRoot, System.StringComparison.Ordinal))
            {
                return 0;
            }

            int removed = 0;
            foreach (string relativePath in ProjectAssetRelativePaths)
            {
                string legacyPath = CombineRootPath(unityProjectRoot, relativePath);
                if (!File.Exists(legacyPath)) continue;

                File.Delete(legacyPath);
                removed++;
            }

            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github", "workflows"));
            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github", "actions", "build-android"));
            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github", "actions", "build-ios"));
            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github", "actions"));
            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github", "scripts"));
            DeleteDirectoryIfEmpty(Path.Combine(unityProjectRoot, ".github"));
            return removed;
        }

        private static int RemoveObsoleteRepositoryAssets()
        {
            int removed = 0;
            foreach (string relativePath in ObsoleteProjectAssetRelativePaths)
            {
                string path = GetProjectPath(relativePath);
                if (string.IsNullOrEmpty(path) || !File.Exists(path)) continue;

                File.Delete(path);
                removed++;
            }

            return removed;
        }

        private static void DeleteDirectoryIfEmpty(string path)
        {
            if (Directory.Exists(path) && Directory.GetFileSystemEntries(path).Length == 0)
                Directory.Delete(path);
        }

        private static string CombineRootPath(string rootPath, string relativePath)
        {
            string normalizedRelativePath = relativePath.Replace('/', Path.DirectorySeparatorChar);
            return Path.GetFullPath(Path.Combine(rootPath, normalizedRelativePath));
        }

        private static bool FilesMatch(string sourcePath, string targetPath)
        {
            byte[] sourceBytes = File.ReadAllBytes(sourcePath);
            byte[] targetBytes = File.ReadAllBytes(targetPath);
            if (sourceBytes.Length != targetBytes.Length)
                return false;

            for (int i = 0; i < sourceBytes.Length; i++)
            {
                if (sourceBytes[i] != targetBytes[i])
                    return false;
            }

            return true;
        }
    }
}

#endif
