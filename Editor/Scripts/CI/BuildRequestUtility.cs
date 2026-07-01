#if UNITY_EDITOR

using System;
using System.Collections.Generic;
using System.IO;
using ActionFit.BuildSetting.Editor;
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

        public static string AbsolutePath => Path.GetFullPath(Path.Combine(ProjectRoot, RelativePath));

        private static string ProjectRoot => Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

        public static BuildRequest Create(
            BuildSettingsSO settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget,
            BuildRequestDistributionProfile distributionProfile,
            string[] slackMentions = null)
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

            return new BuildRequest
            {
                triggerSource = BuildRequest.BuildCommitTriggerSource,
                platform = resolvedPlatform,
                buildKind = buildKind,
                uploadTarget = uploadTarget,
                distributionProfile = distributionProfile,
                buildVersion = settings.buildVersion,
                bundleNo = settings.bundleNo,
                buildFileName = settings.buildFileName,
                androidPackageName = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(settings.androidPackageName, EmptyAndroidPackagePlaceholder) : "",
                iosBundleId = UsesIos(resolvedPlatform) ? SanitizeSettingValue(settings.iosPackageName, EmptyIosBundlePlaceholder) : "",
                iosDevelopmentTeamId = "",
                androidKeystoreFileName = UsesAndroid(resolvedPlatform) ? GetAndroidKeystoreFileName(settings) : "",
                androidKeystoreBase64 = UsesAndroid(resolvedPlatform) ? GetAndroidKeystoreBase64(settings) : "",
                androidKeystorePassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(settings.keystorePassword, EmptyKeystorePasswordPlaceholder) : "",
                androidAliasPassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(settings.aliasPassword, EmptyAliasPasswordPlaceholder) : "",
                googlePlayServiceAccountJson = "",
                appStoreConnectApiKeyId = "",
                appStoreConnectIssuerId = "",
                appStoreConnectApiKeyP8 = "",
                androidKeyaliasName = UsesAndroid(resolvedPlatform) ? GetAndroidKeyaliasName(settings) : "",
                slackMentions = NormalizeSlackMentions(slackMentions),
                sourceBranch = RunGitCommand("rev-parse --abbrev-ref HEAD"),
                sourceCommit = RunGitCommand("rev-parse HEAD"),
                createdAtUtc = DateTime.UtcNow.ToString("o")
            };
        }

        public static BuildRequest Create(
            BuildSettingsSO settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget)
        {
            return Create(settings, platform, buildKind, uploadTarget, BuildRequestDistributionProfile.Actionfit);
        }

        public static string GetAndroidKeyaliasName(BuildSettingsSO settings)
        {
            if (settings == null) return "";

            return SanitizeSettingValue(settings.keyStoreAlias, EmptyKeystoreAliasPlaceholder);
        }

        private static string GetAndroidKeystoreFileName(BuildSettingsSO settings)
        {
            string keystorePath = ResolveAndroidKeystorePath(settings);
            return string.IsNullOrEmpty(keystorePath) ? "" : Path.GetFileName(keystorePath);
        }

        private static string GetAndroidKeystoreBase64(BuildSettingsSO settings)
        {
            string keystorePath = ResolveAndroidKeystorePath(settings);
            if (string.IsNullOrEmpty(keystorePath)) return "";

            try
            {
                byte[] bytes = File.ReadAllBytes(keystorePath);
                return Convert.ToBase64String(bytes);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[BuildRequestUtility] Failed to read Android keystore file: {keystorePath}\n{ex}");
                return "";
            }
        }

        private static string ResolveAndroidKeystorePath(BuildSettingsSO settings)
        {
            if (settings == null) return "";

            string configuredPath = SanitizeSettingValue(settings.keyStorePath, EmptyKeystorePathPlaceholder);
            string resolvedPath = ResolveKeystorePath(configuredPath);
            if (!string.IsNullOrEmpty(resolvedPath)) return resolvedPath;

            string playerSettingsPath = PlayerSettings.Android.keystoreName;
            resolvedPath = ResolveKeystorePath(playerSettingsPath);
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
                : Path.GetFullPath(Path.Combine(ProjectRoot, normalizedPath));

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

            string directory = Path.GetDirectoryName(AbsolutePath);
            if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);

            File.WriteAllText(AbsolutePath, JsonUtility.ToJson(request, true));
            AssetDatabase.Refresh();
            Debug.Log($"[BuildRequestUtility] BuildRequest saved: {RelativePath}");
            return true;
        }

        public static BuildRequest Load()
        {
            if (!File.Exists(AbsolutePath))
            {
                Debug.LogError($"[BuildRequestUtility] BuildRequest not found: {RelativePath}");
                return null;
            }

            string json = File.ReadAllText(AbsolutePath);
            BuildRequest request = JsonUtility.FromJson<BuildRequest>(json);
            if (request == null)
            {
                Debug.LogError($"[BuildRequestUtility] Failed to parse BuildRequest: {RelativePath}");
                return null;
            }

            return request;
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

        private static string RunGitCommand(string args)
        {
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = args,
                    WorkingDirectory = ProjectRoot,
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
}

#endif
