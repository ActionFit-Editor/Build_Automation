#if UNITY_EDITOR

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using Process = System.Diagnostics.Process;
using ProcessStartInfo = System.Diagnostics.ProcessStartInfo;

namespace ActionFit.BuildAutomation.Editor
{
    public static class BuildRequestUtility
    {
        public const string RelativePath = ".build/build_request.json";
        private const string EmptyAndroidPackagePlaceholder = "[Enter Android Package Name]";
        private const string EmptyIosBundlePlaceholder = "[Enter iOS Bundle ID]";
        private const string EmptyKeystorePathPlaceholder = "[Enter Keystore Path]";
        private const string EmptyKeystoreAliasPlaceholder = "[Enter Keystore Alias]";
        private const string EmptyKeystorePasswordPlaceholder = "[Enter KeyStore Password]";
        private const string EmptyAliasPasswordPlaceholder = "[Enter Alias Password]";

        public static string UnityProjectRoot => BuildAutomationProjectPaths.UnityProjectRoot;
        public static string RepositoryRoot => BuildAutomationProjectPaths.GetRepositoryRootOrThrow();
        public static string UnityProjectPath => BuildAutomationProjectPaths.GetUnityProjectPathOrThrow();
        public static string AbsolutePath => Path.GetFullPath(Path.Combine(RepositoryRoot, RelativePath));

        public static BuildRequest Create(
            ScriptableObject settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget,
            BuildRequestDistributionProfile distributionProfile,
            string[] slackMentions = null,
            bool autoConfigureBuildSymbols = true)
        {
            if (settings == null)
            {
                Debug.LogError("[BuildRequestUtility] BuildSettingsSO is null");
                return null;
            }

            BuildRequestPlatform resolvedPlatform = ResolvePlatform(platform);
            if (resolvedPlatform == BuildRequestPlatform.None)
            {
                Debug.LogError("[BuildRequestUtility] BuildRequest platform is not selected");
                return null;
            }

            if (!BuildAutomationProjectPaths.TryGetCurrentLayout(
                    out string repositoryRoot,
                    out string unityProjectPath,
                    out string layoutError))
            {
                Debug.LogError($"[BuildRequestUtility] {layoutError}");
                return null;
            }

            return new BuildRequest
            {
                triggerSource = BuildRequest.BuildCommitTriggerSource,
                unityProjectPath = unityProjectPath,
                autoConfigureBuildSymbols = autoConfigureBuildSymbols,
                platform = resolvedPlatform,
                buildKind = buildKind,
                uploadTarget = uploadTarget,
                distributionProfile = distributionProfile,
                buildVersion = BuildSettingBridge.GetString(settings, "buildVersion"),
                bundleNo = BuildSettingBridge.GetString(settings, "bundleNo"),
                buildFileName = BuildSettingBridge.GetString(settings, "buildFileName"),
                androidPackageName = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(BuildSettingBridge.GetString(settings, "androidPackageName"), EmptyAndroidPackagePlaceholder) : "",
                iosBundleId = UsesIos(resolvedPlatform) ? SanitizeSettingValue(BuildSettingBridge.GetString(settings, "iosPackageName"), EmptyIosBundlePlaceholder) : "",
                androidKeystoreFileName = UsesAndroid(resolvedPlatform) ? GetAndroidKeystoreFileName(settings) : "",
                androidKeystoreBase64 = UsesAndroid(resolvedPlatform) ? GetAndroidKeystoreBase64(settings) : "",
                androidKeystorePassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(BuildSettingBridge.GetString(settings, "keystorePassword"), EmptyKeystorePasswordPlaceholder) : "",
                androidAliasPassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(BuildSettingBridge.GetString(settings, "aliasPassword"), EmptyAliasPasswordPlaceholder) : "",
                androidKeyaliasName = UsesAndroid(resolvedPlatform) ? GetAndroidKeyaliasName(settings) : "",
                slackMentions = NormalizeSlackMentions(slackMentions),
                sourceBranch = RunGitCommand(repositoryRoot, "rev-parse --abbrev-ref HEAD"),
                sourceCommit = RunGitCommand(repositoryRoot, "rev-parse HEAD"),
                createdAtUtc = DateTime.UtcNow.ToString("o")
            };
        }

        public static BuildRequest Create(
            ScriptableObject settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget)
        {
            return Create(settings, platform, buildKind, uploadTarget, BuildRequestDistributionProfile.Actionfit);
        }

        public static string GetAndroidKeyaliasName(ScriptableObject settings)
        {
            if (settings == null) return "";

            return SanitizeSettingValue(BuildSettingBridge.GetString(settings, "keyStoreAlias"), EmptyKeystoreAliasPlaceholder);
        }

        private static string GetAndroidKeystoreFileName(ScriptableObject settings)
        {
            string keystorePath = ResolveAndroidKeystorePath(settings);
            return string.IsNullOrEmpty(keystorePath) ? "" : Path.GetFileName(keystorePath);
        }

        private static string GetAndroidKeystoreBase64(ScriptableObject settings)
        {
            string keystorePath = ResolveAndroidKeystorePath(settings);
            if (string.IsNullOrEmpty(keystorePath)) return "";

            try
            {
                byte[] bytes = File.ReadAllBytes(keystorePath);
                return Convert.ToBase64String(bytes);
            }
            catch (Exception exception)
            {
                Debug.LogError($"[BuildRequestUtility] Failed to read Android keystore file: {keystorePath}\n{exception}");
                return "";
            }
        }

        private static string ResolveAndroidKeystorePath(ScriptableObject settings)
        {
            if (settings == null) return "";

            string configuredPath = SanitizeSettingValue(
                BuildSettingBridge.GetString(settings, "keyStorePath"),
                EmptyKeystorePathPlaceholder);
            string resolvedPath = ResolveKeystorePath(configuredPath);
            if (!string.IsNullOrEmpty(resolvedPath)) return resolvedPath;

            resolvedPath = ResolveKeystorePath(PlayerSettings.Android.keystoreName);
            if (!string.IsNullOrEmpty(resolvedPath)) return resolvedPath;

            if (!string.IsNullOrEmpty(configuredPath))
                Debug.LogWarning($"[BuildRequestUtility] Android keystore file not found: {configuredPath}");

            return "";
        }

        private static string ResolveKeystorePath(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return "";

            string normalizedPath = path.Trim();
            const string InProjectPrefix = "{inproject}:";
            if (normalizedPath.StartsWith(InProjectPrefix, StringComparison.OrdinalIgnoreCase))
                normalizedPath = normalizedPath.Substring(InProjectPrefix.Length).Trim();

            string absolutePath = Path.IsPathRooted(normalizedPath)
                ? normalizedPath
                : Path.GetFullPath(Path.Combine(UnityProjectRoot, normalizedPath));

            return File.Exists(absolutePath) ? absolutePath : "";
        }

        private static bool UsesAndroid(BuildRequestPlatform platform)
        {
            return platform == BuildRequestPlatform.Android || platform == BuildRequestPlatform.Both;
        }

        private static bool UsesIos(BuildRequestPlatform platform)
        {
            return platform == BuildRequestPlatform.iOS || platform == BuildRequestPlatform.Both;
        }

        private static string SanitizeSettingValue(string value, string placeholder)
        {
            if (string.IsNullOrWhiteSpace(value)) return "";

            string result = value.Trim();
            return result == placeholder ? "" : result;
        }

        private static string[] NormalizeSlackMentions(string[] values)
        {
            if (values == null || values.Length == 0) return Array.Empty<string>();

            var mentions = new List<string>();
            foreach (string value in values)
            {
                string mention = value?.Trim();
                if (string.IsNullOrEmpty(mention) || mentions.Contains(mention)) continue;
                mentions.Add(mention);
            }

            return mentions.ToArray();
        }

        public static bool Save(BuildRequest request)
        {
            if (request == null)
            {
                Debug.LogError("[BuildRequestUtility] BuildRequest is null");
                return false;
            }

            if (!TryGetRequestPath(out string requestPath, out string pathError))
            {
                Debug.LogError($"[BuildRequestUtility] {pathError}");
                return false;
            }

            string directory = Path.GetDirectoryName(requestPath);
            if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);

            RemoveLegacyUnityProjectRequest(requestPath);
            File.WriteAllText(requestPath, JsonUtility.ToJson(request, true));
            AssetDatabase.Refresh();
            Debug.Log($"[BuildRequestUtility] BuildRequest saved: {requestPath}");
            return true;
        }

        public static BuildRequest Load()
        {
            if (!TryGetRequestPath(out string requestPath, out string pathError))
            {
                Debug.LogError($"[BuildRequestUtility] {pathError}");
                return null;
            }

            if (!File.Exists(requestPath))
            {
                Debug.LogError($"[BuildRequestUtility] BuildRequest not found: {requestPath}");
                return null;
            }

            string json = File.ReadAllText(requestPath);
            BuildRequest request = JsonUtility.FromJson<BuildRequest>(json);
            if (request == null)
            {
                Debug.LogError($"[BuildRequestUtility] Failed to parse BuildRequest: {RelativePath}");
                return null;
            }

            if (request.schemaVersion != 11)
            {
                Debug.LogError(
                    $"[BuildRequestUtility] Unsupported BuildRequest schema: {request.schemaVersion}. " +
                    "Open AutoBuild and create a schema 11 request.");
                return null;
            }

            if (!BuildAutomationProjectPaths.TryNormalizeUnityProjectPath(
                    request.unityProjectPath,
                    out string normalizedUnityProjectPath,
                    out string normalizeError))
            {
                Debug.LogError($"[BuildRequestUtility] Invalid unityProjectPath: {normalizeError}");
                return null;
            }

            request.unityProjectPath = normalizedUnityProjectPath;

            if (!BuildAutomationProjectPaths.TryGetCurrentLayout(
                    out _,
                    out string currentUnityProjectPath,
                    out string layoutError))
            {
                Debug.LogError($"[BuildRequestUtility] {layoutError}");
                return null;
            }

            if (!string.Equals(request.unityProjectPath, currentUnityProjectPath, StringComparison.Ordinal))
            {
                Debug.LogError(
                    $"[BuildRequestUtility] BuildRequest unityProjectPath mismatch. " +
                    $"request={request.unityProjectPath}, current={currentUnityProjectPath}");
                return null;
            }

            return request;
        }

        internal static bool TryGetRepositoryRoot(out string repositoryRoot, out string error)
        {
            return BuildAutomationProjectPaths.TryGetCurrentLayout(
                out repositoryRoot,
                out _,
                out error);
        }

        private static bool TryGetRequestPath(out string requestPath, out string error)
        {
            requestPath = null;
            if (!TryGetRepositoryRoot(out string repositoryRoot, out error))
                return false;

            requestPath = Path.GetFullPath(Path.Combine(repositoryRoot, RelativePath));
            return true;
        }

        private static void RemoveLegacyUnityProjectRequest(string requestPath)
        {
            string legacyPath = Path.GetFullPath(Path.Combine(UnityProjectRoot, RelativePath));
            if (string.Equals(legacyPath, requestPath, StringComparison.Ordinal) || !File.Exists(legacyPath))
                return;

            File.Delete(legacyPath);
            string legacyDirectory = Path.GetDirectoryName(legacyPath);
            if (!string.IsNullOrEmpty(legacyDirectory) &&
                Directory.Exists(legacyDirectory) &&
                Directory.GetFileSystemEntries(legacyDirectory).Length == 0)
            {
                Directory.Delete(legacyDirectory);
            }

            Debug.Log($"[BuildRequestUtility] Removed legacy Unity-project request: {legacyPath}");
        }

        private static BuildRequestPlatform ResolvePlatform(BuildRequestPlatform platform)
        {
            if (platform != BuildRequestPlatform.Current) return platform;

            return EditorUserBuildSettings.activeBuildTarget switch
            {
                BuildTarget.Android => BuildRequestPlatform.Android,
                BuildTarget.iOS => BuildRequestPlatform.iOS,
                _ => BuildRequestPlatform.Current
            };
        }

        private static string RunGitCommand(string workingDirectory, string args)
        {
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = args,
                    WorkingDirectory = workingDirectory,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using (var process = Process.Start(startInfo))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    return process.ExitCode == 0 ? output.Trim() : "";
                }
            }
            catch (Exception e)
            {
                Debug.LogError($"[BuildRequestUtility] git {args} failed: {e.Message}");
                return "";
            }
        }
    }

    internal static class BuildAutomationProjectPaths
    {
        private static string _cachedUnityProjectRoot;
        private static string _cachedRepositoryRoot;
        private static string _cachedUnityProjectPath;

        internal static string UnityProjectRoot =>
            Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

        internal static string GetRepositoryRootOrThrow()
        {
            if (TryGetCurrentLayout(out string repositoryRoot, out _, out string error))
                return repositoryRoot;

            throw new InvalidOperationException(error);
        }

        internal static string GetUnityProjectPathOrThrow()
        {
            if (TryGetCurrentLayout(out _, out string unityProjectPath, out string error))
                return unityProjectPath;

            throw new InvalidOperationException(error);
        }

        internal static bool TryGetCurrentLayout(
            out string repositoryRoot,
            out string unityProjectPath,
            out string error)
        {
            repositoryRoot = null;
            unityProjectPath = null;

            string unityProjectRoot = UnityProjectRoot;
            if (string.Equals(_cachedUnityProjectRoot, unityProjectRoot, StringComparison.Ordinal) &&
                !string.IsNullOrEmpty(_cachedRepositoryRoot) &&
                !string.IsNullOrEmpty(_cachedUnityProjectPath))
            {
                repositoryRoot = _cachedRepositoryRoot;
                unityProjectPath = _cachedUnityProjectPath;
                error = null;
                return true;
            }

            if (!TryGetRepositoryRoot(unityProjectRoot, out repositoryRoot, out error))
                return false;

            if (!TryGetUnityProjectPath(repositoryRoot, unityProjectRoot, out unityProjectPath, out error))
                return false;

            _cachedUnityProjectRoot = unityProjectRoot;
            _cachedRepositoryRoot = repositoryRoot;
            _cachedUnityProjectPath = unityProjectPath;
            return true;
        }

        internal static bool TryGetRepositoryRoot(
            string startPath,
            out string repositoryRoot,
            out string error)
        {
            repositoryRoot = null;
            error = null;

            if (string.IsNullOrWhiteSpace(startPath) || !Directory.Exists(startPath))
            {
                error = $"Unity project root does not exist: {startPath}";
                return false;
            }

            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = "rev-parse --show-toplevel",
                    WorkingDirectory = Path.GetFullPath(startPath),
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using (var process = Process.Start(startInfo))
                {
                    string output = process.StandardOutput.ReadToEnd().Trim();
                    string standardError = process.StandardError.ReadToEnd().Trim();
                    process.WaitForExit();

                    if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
                    {
                        error = string.IsNullOrWhiteSpace(standardError)
                            ? $"Git repository root was not found from: {startPath}"
                            : $"Git repository root was not found from {startPath}: {standardError}";
                        return false;
                    }

                    repositoryRoot = Path.GetFullPath(output);
                    return true;
                }
            }
            catch (Exception exception)
            {
                error = $"Failed to resolve Git repository root from {startPath}: {exception.Message}";
                return false;
            }
        }

        internal static bool TryGetUnityProjectPath(
            string repositoryRoot,
            string unityProjectRoot,
            out string unityProjectPath,
            out string error)
        {
            unityProjectPath = null;
            error = null;

            if (string.IsNullOrWhiteSpace(repositoryRoot) || string.IsNullOrWhiteSpace(unityProjectRoot))
            {
                error = "Repository root and Unity project root are required.";
                return false;
            }

            string normalizedRepositoryRoot = Path.GetFullPath(repositoryRoot);
            string normalizedUnityProjectRoot = Path.GetFullPath(unityProjectRoot);
            string relativePath = Path.GetRelativePath(normalizedRepositoryRoot, normalizedUnityProjectRoot)
                .Replace(Path.DirectorySeparatorChar, '/');

            if (!TryNormalizeUnityProjectPath(relativePath, out unityProjectPath, out error))
                return false;

            string resolvedUnityProjectRoot = unityProjectPath == "."
                ? normalizedRepositoryRoot
                : Path.GetFullPath(Path.Combine(normalizedRepositoryRoot, unityProjectPath));

            if (!string.Equals(resolvedUnityProjectRoot, normalizedUnityProjectRoot, StringComparison.Ordinal))
            {
                error = $"Unity project root is outside the Git repository. repo={normalizedRepositoryRoot}, project={normalizedUnityProjectRoot}";
                unityProjectPath = null;
                return false;
            }

            return true;
        }

        internal static bool TryNormalizeUnityProjectPath(
            string value,
            out string normalizedPath,
            out string error)
        {
            normalizedPath = null;
            error = null;

            string candidate = string.IsNullOrWhiteSpace(value) ? "." : value.Trim().Replace('\\', '/');
            if (candidate.Any(character => char.IsControl(character)))
            {
                error = "The path contains control characters.";
                return false;
            }

            if (Path.IsPathRooted(candidate))
            {
                error = $"The path must be relative: {candidate}";
                return false;
            }

            var segments = new List<string>();
            foreach (string segment in candidate.Split('/'))
            {
                if (string.IsNullOrEmpty(segment) || segment == ".") continue;
                if (segment == "..")
                {
                    error = $"The path escapes the repository: {candidate}";
                    return false;
                }

                segments.Add(segment);
            }

            normalizedPath = segments.Count == 0 ? "." : string.Join("/", segments);
            return true;
        }
    }
}

#endif
