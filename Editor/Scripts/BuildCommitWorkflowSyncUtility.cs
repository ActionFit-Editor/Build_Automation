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

        private const string PackageName = "com.actionfit.buildautomation";

        internal static bool IsWorkflowCurrent()
        {
            string templatePath = GetTemplatePath();
            string workflowPath = GetWorkflowPath();

            return !string.IsNullOrEmpty(templatePath) &&
                   File.Exists(templatePath) &&
                   File.Exists(workflowPath) &&
                   FilesMatch(templatePath, workflowPath);
        }

        internal static bool WorkflowExists()
        {
            return File.Exists(GetWorkflowPath());
        }

        internal static string GetStatusMessage()
        {
            string templatePath = GetTemplatePath();
            string workflowPath = GetWorkflowPath();

            if (string.IsNullOrEmpty(templatePath) || !File.Exists(templatePath))
                return $"Template missing: {TemplateRelativePath}";

            if (!File.Exists(workflowPath))
                return $"Workflow missing: {WorkflowRelativePath}";

            return FilesMatch(templatePath, workflowPath)
                ? $"Workflow is up to date: {WorkflowRelativePath}"
                : $"Workflow differs from package template: {WorkflowRelativePath}";
        }

        internal static bool TrySync(out string message)
        {
            string templatePath = GetTemplatePath();
            if (string.IsNullOrEmpty(templatePath) || !File.Exists(templatePath))
            {
                message = $"Template not found: {TemplateRelativePath}";
                return false;
            }

            string workflowPath = GetWorkflowPath();
            string workflowDirectory = Path.GetDirectoryName(workflowPath);
            if (!string.IsNullOrEmpty(workflowDirectory))
                Directory.CreateDirectory(workflowDirectory);

            if (File.Exists(workflowPath) && FilesMatch(templatePath, workflowPath))
            {
                message = $"Already up to date: {WorkflowRelativePath}";
                return true;
            }

            File.Copy(templatePath, workflowPath, true);
            message = $"Updated {WorkflowRelativePath} from {TemplateRelativePath}";
            return true;
        }

        private static string GetTemplatePath()
        {
            string packageRoot = GetPackageRoot();
            return string.IsNullOrEmpty(packageRoot)
                ? null
                : CombineRootPath(packageRoot, TemplateRelativePath);
        }

        private static string GetWorkflowPath()
        {
            return CombineRootPath(GetProjectRoot(), WorkflowRelativePath);
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
