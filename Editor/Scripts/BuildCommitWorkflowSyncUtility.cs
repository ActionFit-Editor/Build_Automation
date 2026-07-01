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
        internal const string ScriptTemplateRelativePath = ".github/scripts/validate-local-runner-secrets.sh";
        internal const string ScriptRelativePath = ".github/scripts/validate-local-runner-secrets.sh";

        private const string PackageName = "com.actionfit.buildautomation";

        internal static bool IsWorkflowCurrent()
        {
            return PackageFileMatchesProjectFile(TemplateRelativePath, WorkflowRelativePath) &&
                   PackageFileMatchesProjectFile(ScriptTemplateRelativePath, ScriptRelativePath);
        }

        internal static bool WorkflowExists()
        {
            return File.Exists(GetWorkflowPath());
        }

        internal static string GetStatusMessage()
        {
            string templatePath = GetPackagePath(TemplateRelativePath);
            string scriptTemplatePath = GetPackagePath(ScriptTemplateRelativePath);
            string workflowPath = GetProjectPath(WorkflowRelativePath);
            string scriptPath = GetProjectPath(ScriptRelativePath);

            if (string.IsNullOrEmpty(templatePath) || !File.Exists(templatePath))
                return $"Template missing: {TemplateRelativePath}";

            if (string.IsNullOrEmpty(scriptTemplatePath) || !File.Exists(scriptTemplatePath))
                return $"Template missing: {ScriptTemplateRelativePath}";

            if (!File.Exists(workflowPath) || !File.Exists(scriptPath))
                return $"Workflow assets missing: {WorkflowRelativePath}, {ScriptRelativePath}";

            return IsWorkflowCurrent()
                ? $"Workflow assets are up to date: {WorkflowRelativePath}, {ScriptRelativePath}"
                : $"Workflow assets differ from package templates: {WorkflowRelativePath}, {ScriptRelativePath}";
        }

        internal static bool TrySync(out string message)
        {
            if (!TrySyncPackageFile(TemplateRelativePath, WorkflowRelativePath, out string workflowMessage))
            {
                message = workflowMessage;
                return false;
            }

            if (!TrySyncPackageFile(ScriptTemplateRelativePath, ScriptRelativePath, out string scriptMessage))
            {
                message = scriptMessage;
                return false;
            }

            message = $"{workflowMessage}; {scriptMessage}";
            return true;
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
