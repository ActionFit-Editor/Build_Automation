#if UNITY_EDITOR

using System;
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
        private const string EmptyKeystoreAliasPlaceholder = "[Enter Keystore Alias]";
        private const string EmptyKeystorePasswordPlaceholder = "[Enter KeyStore Password]";
        private const string EmptyAliasPasswordPlaceholder = "[Enter Alias Password]";
        private const string EmptyIosDevelopmentTeamPlaceholder = "[Enter Apple Team ID]";

        public static string AbsolutePath => Path.GetFullPath(Path.Combine(ProjectRoot, RelativePath));

        private static string ProjectRoot => Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

        public static BuildRequest Create(
            BuildSettingsSO settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget,
            BuildRequestDistributionProfile distributionProfile,
            string googlePlayServiceAccountJson = "",
            string appStoreConnectApiKeyId = "",
            string appStoreConnectIssuerId = "",
            string appStoreConnectApiKeyP8 = "")
        {
            if (settings == null)
            {
                Debug.LogError("[BuildRequestUtility] BuildSettingsSO is null");
                return null;
            }

            BuildRequestPlatform resolvedPlatform = ResolvePlatform(platform);
            string selectedGooglePlayServiceAccountJson = PickOptionalText(
                googlePlayServiceAccountJson,
                settings.buildCommitGooglePlayServiceAccountJson);
            string selectedAppStoreConnectApiKeyId = PickOptionalText(
                appStoreConnectApiKeyId,
                settings.buildCommitAppStoreConnectApiKeyId);
            string selectedAppStoreConnectIssuerId = PickOptionalText(
                appStoreConnectIssuerId,
                settings.buildCommitAppStoreConnectIssuerId);
            string selectedAppStoreConnectApiKeyP8 = PickOptionalText(
                appStoreConnectApiKeyP8,
                settings.buildCommitAppStoreConnectApiKeyP8);

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
                iosDevelopmentTeamId = UsesIos(resolvedPlatform) ? SanitizeSettingValue(settings.developmentTeamId, EmptyIosDevelopmentTeamPlaceholder) : "",
                androidKeystorePassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(settings.keystorePassword, EmptyKeystorePasswordPlaceholder) : "",
                androidAliasPassword = UsesAndroid(resolvedPlatform) ? SanitizeSettingValue(settings.aliasPassword, EmptyAliasPasswordPlaceholder) : "",
                googlePlayServiceAccountJson = UsesAndroidUpload(resolvedPlatform, uploadTarget) ? NormalizeOptionalText(selectedGooglePlayServiceAccountJson) : "",
                appStoreConnectApiKeyId = UsesIosUpload(resolvedPlatform, uploadTarget) ? NormalizeOptionalText(selectedAppStoreConnectApiKeyId) : "",
                appStoreConnectIssuerId = UsesIosUpload(resolvedPlatform, uploadTarget) ? NormalizeOptionalText(selectedAppStoreConnectIssuerId) : "",
                appStoreConnectApiKeyP8 = UsesIosUpload(resolvedPlatform, uploadTarget) ? NormalizeOptionalText(selectedAppStoreConnectApiKeyP8) : "",
                androidKeyaliasName = UsesAndroid(resolvedPlatform) ? GetAndroidKeyaliasName(settings) : "",
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

        private static bool UsesAndroid(BuildRequestPlatform platform)
        {
            return platform == BuildRequestPlatform.Android || platform == BuildRequestPlatform.Both;
        }

        private static bool UsesIos(BuildRequestPlatform platform)
        {
            return platform == BuildRequestPlatform.iOS || platform == BuildRequestPlatform.Both;
        }

        private static bool UsesAndroidUpload(BuildRequestPlatform platform, BuildRequestUploadTarget uploadTarget)
        {
            return UsesAndroid(platform) &&
                   (uploadTarget == BuildRequestUploadTarget.GooglePlayInternal ||
                    uploadTarget == BuildRequestUploadTarget.GooglePlayInternalAndTestFlight);
        }

        private static bool UsesIosUpload(BuildRequestPlatform platform, BuildRequestUploadTarget uploadTarget)
        {
            return UsesIos(platform) &&
                   (uploadTarget == BuildRequestUploadTarget.TestFlight ||
                    uploadTarget == BuildRequestUploadTarget.GooglePlayInternalAndTestFlight);
        }

        private static string SanitizeSettingValue(string value, string placeholder)
        {
            if (string.IsNullOrWhiteSpace(value)) return "";

            string result = value.Trim();
            return result == placeholder ? "" : result;
        }

        private static string PickOptionalText(string value, string fallback)
        {
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }

        private static string NormalizeOptionalText(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
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
