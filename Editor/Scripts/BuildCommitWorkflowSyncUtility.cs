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
        internal const string ValidateSecretsScriptRelativePath = ".github/scripts/validate-local-runner-secrets.sh";
        internal const string ResolveUnityScriptRelativePath = ".github/scripts/resolve-unity-editor.sh";

        private const string PackageName = "com.actionfit.buildautomation";
        private static readonly string[] PackageAssetRelativePaths =
        {
            TemplateRelativePath,
            ValidateSecretsScriptRelativePath,
            ResolveUnityScriptRelativePath
        };

        private static readonly string[] ProjectAssetRelativePaths =
        {
            WorkflowRelativePath,
            ValidateSecretsScriptRelativePath,
            ResolveUnityScriptRelativePath
        };

        internal static bool IsWorkflowCurrent()
        {
            for (int i = 0; i < PackageAssetRelativePaths.Length; i++)
            {
                if (!PackageFileMatchesProjectFile(PackageAssetRelativePaths[i], ProjectAssetRelativePaths[i]))
                    return false;
            }

            return true;
        }

        internal static bool WorkflowExists()
        {
            return File.Exists(GetWorkflowPath());
        }

        internal static string GetStatusMessage()
        {
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
                    return $"Workflow asset missing: {ProjectAssetRelativePaths[i]}";
            }

            return IsWorkflowCurrent()
                ? $"Workflow assets are up to date: {GetWorkflowAssetSummary()}"
                : $"Workflow assets differ from package templates: {GetWorkflowAssetSummary()}";
        }

        internal static bool TrySync(out string message)
        {
            message = "";

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

            return true;
        }

        internal static string GetWorkflowAssetSummary()
        {
            return $"{WorkflowRelativePath}, {ValidateSecretsScriptRelativePath}, {ResolveUnityScriptRelativePath}";
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

        private static string GetWorkflowPath()
        {
            return GetProjectPath(WorkflowRelativePath);
        }

        private static string GetProjectPath(string relativePath)
        {
            return CombineRootPath(GetProjectRoot(), relativePath);
        }

        private static string GetPackageRoot()
        {
            PackageInfo packageInfo = PackageInfo.FindForAssembly(typeof(BuildCommitWorkflowSyncUtility).Assembly);
            if (packageInfo != null && !string.IsNullOrEmpty(packageInfo.resolvedPath))
                return Path.GetFullPath(packageInfo.resolvedPath);

            string embeddedPath = Path.GetFullPath(Path.Combine(GetProjectRoot(), "Packages", PackageName));
            return Directory.Exists(embeddedPath) ? embeddedPath : null;
        }

        private static string GetProjectRoot()
        {
            return Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
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
