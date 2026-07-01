#if UNITY_EDITOR

using System;
using System.IO;
using ActionFit.BuildSetting.Editor;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    public static class CIBuildEntry
    {
        public static void BuildFromRequest()
        {
            int exitCode = ExecuteBuildFromRequest();
            EditorApplication.Exit(exitCode);
        }

        private static int ExecuteBuildFromRequest()
        {
            BuildRequest request = BuildRequestUtility.Load();
            if (request == null) return 1;

            if (request.triggerSource != BuildRequest.BuildCommitTriggerSource)
            {
                Debug.LogError($"[CIBuildEntry] Unsupported trigger source: {request.triggerSource}");
                return 1;
            }

            BuildSettingsSO settings = BuildSettingsSO.FindSettingsAsset();
            if (settings == null)
            {
                Debug.LogError("[CIBuildEntry] BuildSettingsSO not found");
                return 1;
            }

            ApplyRequest(settings, request);
            BuildSettingsApplier.ApplyVersionSettings(settings);
            ApplyPlayerIdentifiers(settings);

            BuildReport report = RunBuild(settings, request);
            if (report == null)
            {
                Debug.LogError("[CIBuildEntry] Build report is null");
                return 1;
            }

            BuildSummary summary = report.summary;
            Debug.Log($"[CIBuildEntry] Build result: {summary.result}, output={summary.outputPath}");
            return summary.result == BuildResult.Succeeded ? 0 : 1;
        }

        private static void ApplyRequest(BuildSettingsSO settings, BuildRequest request)
        {
            string androidAlias = request.androidKeyaliasName?.Trim();
            string androidPackageName = request.androidPackageName?.Trim();
            string iosBundleId = request.iosBundleId?.Trim();
            string iosDevelopmentTeamId = PickEnvironmentOrRequest("IOS_DEVELOPMENT_TEAM_ID", request.iosDevelopmentTeamId);

            if (!string.IsNullOrEmpty(request.buildVersion)) settings.buildVersion = request.buildVersion;
            if (!string.IsNullOrEmpty(request.bundleNo)) settings.bundleNo = request.bundleNo;
            if (!string.IsNullOrEmpty(request.buildFileName)) settings.buildFileName = request.buildFileName;
            if (!string.IsNullOrEmpty(androidPackageName)) settings.androidPackageName = androidPackageName;
            if (!string.IsNullOrEmpty(iosBundleId)) settings.iosPackageName = iosBundleId;
            if (!string.IsNullOrEmpty(iosDevelopmentTeamId)) settings.developmentTeamId = iosDevelopmentTeamId;
            if (!string.IsNullOrEmpty(androidAlias)) settings.keyStoreAlias = androidAlias;
            settings.saveFileInProject = true;

            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CIBuildEntry] Request applied: trigger={request.triggerSource}, platform={request.platform}, kind={request.buildKind}, upload={request.uploadTarget}, profile={request.distributionProfile}, androidPackage={androidPackageName}, iosBundle={iosBundleId}, iosTeamId={iosDevelopmentTeamId}, androidAlias={androidAlias}");
        }

        private static void ApplyPlayerIdentifiers(BuildSettingsSO settings)
        {
            if (!string.IsNullOrWhiteSpace(settings.androidPackageName))
                PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, settings.androidPackageName.Trim());

            if (!string.IsNullOrWhiteSpace(settings.iosPackageName))
                PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.iOS, settings.iosPackageName.Trim());
        }

        private static BuildReport RunBuild(BuildSettingsSO settings, BuildRequest request)
        {
            BuildRequestPlatform platform = ResolvePlatform(request.platform);

            switch (platform)
            {
                case BuildRequestPlatform.Android:
#if UNITY_ANDROID
                    ApplyAndroidSigning(request);
                    bool aab = request.buildKind != BuildRequestKind.AndroidApk;
                    return AOSBuildProcess.BuildForCI(settings, aab);
#else
                    Debug.LogError("[CIBuildEntry] Android build requested, but UNITY_ANDROID is not active");
                    return null;
#endif
                case BuildRequestPlatform.iOS:
#if UNITY_IOS
                    return iOSBuildProcess.BuildForCI(settings);
#else
                    Debug.LogError("[CIBuildEntry] iOS build requested, but UNITY_IOS is not active");
                    return null;
#endif
                case BuildRequestPlatform.Both:
                    Debug.LogError("[CIBuildEntry] Both platform requests must be split by the workflow");
                    return null;
                default:
                    Debug.LogError($"[CIBuildEntry] Unsupported platform: {platform}");
                    return null;
            }
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

#if UNITY_ANDROID
        // BuildCommit request signing values are preferred; local runner env values are fallback.
        private static void ApplyAndroidSigning(BuildRequest request)
        {
            string keystorePath = ResolveAndroidKeystorePath(request);
            string keystorePass = PickRequestOrEnvironment(request.androidKeystorePassword, "ANDROID_KEYSTORE_PASS");
            string keyaliasPass = PickRequestOrEnvironment(request.androidAliasPassword, "ANDROID_KEYALIAS_PASS");
            string aliasName = request.androidKeyaliasName?.Trim();
            bool hasAliasName = !string.IsNullOrEmpty(aliasName);

            if (string.IsNullOrEmpty(keystorePath) && !hasAliasName && string.IsNullOrEmpty(keystorePass) && string.IsNullOrEmpty(keyaliasPass))
            {
                Debug.Log("[CIBuildEntry] No keystore env vars found; using project signing settings as-is");
                return;
            }

            PlayerSettings.Android.useCustomKeystore = true;
            if (!string.IsNullOrEmpty(keystorePath))
            {
                if (!File.Exists(keystorePath))
                    throw new FileNotFoundException("[CIBuildEntry] Android keystore file not found", keystorePath);
                else
                    PlayerSettings.Android.keystoreName = keystorePath;
            }
            if (hasAliasName) PlayerSettings.Android.keyaliasName = aliasName;
            if (!string.IsNullOrEmpty(keystorePass)) PlayerSettings.Android.keystorePass = keystorePass;
            if (!string.IsNullOrEmpty(keyaliasPass)) PlayerSettings.Android.keyaliasPass = keyaliasPass;

            Debug.Log($"[CIBuildEntry] Android signing applied: keystorePathInjected={!string.IsNullOrEmpty(keystorePath)}, alias={PlayerSettings.Android.keyaliasName}, keystorePassInjected={!string.IsNullOrEmpty(keystorePass)}, keyaliasPassInjected={!string.IsNullOrEmpty(keyaliasPass)}");
        }
#endif

        private static string ResolveAndroidKeystorePath(BuildRequest request)
        {
            string requestKeystoreBase64 = request.androidKeystoreBase64?.Trim();
            if (!string.IsNullOrEmpty(requestKeystoreBase64))
                return WriteRequestKeystore(request);

            return PickEnvironmentOrRequest("ANDROID_KEYSTORE_PATH", "");
        }

        private static string WriteRequestKeystore(BuildRequest request)
        {
            string fileName = SanitizeFileName(request.androidKeystoreFileName, "android-request.keystore");
            string directory = Path.GetFullPath(Path.Combine(Application.dataPath, "..", ".build", "ci-keystore"));
            string path = Path.Combine(directory, fileName);

            try
            {
                Directory.CreateDirectory(directory);
                byte[] bytes = Convert.FromBase64String(request.androidKeystoreBase64);
                File.WriteAllBytes(path, bytes);
                Debug.Log($"[CIBuildEntry] Android keystore restored from BuildCommit request: {path}");
                return path;
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException("[CIBuildEntry] Failed to restore Android keystore from BuildCommit request", ex);
            }
        }

        private static string SanitizeFileName(string value, string fallback)
        {
            string fileName = Path.GetFileName(value?.Trim());
            if (string.IsNullOrEmpty(fileName)) fileName = fallback;

            foreach (char invalidChar in Path.GetInvalidFileNameChars())
                fileName = fileName.Replace(invalidChar, '_');

            return string.IsNullOrEmpty(fileName) ? fallback : fileName;
        }

        private static string PickEnvironmentOrRequest(string environmentVariableName, string requestValue)
        {
            string environmentValue = Environment.GetEnvironmentVariable(environmentVariableName)?.Trim();
            if (!string.IsNullOrEmpty(environmentValue)) return environmentValue;

            return requestValue?.Trim();
        }

        private static string PickRequestOrEnvironment(string requestValue, string environmentVariableName)
        {
            string normalizedRequestValue = requestValue?.Trim();
            if (!string.IsNullOrEmpty(normalizedRequestValue)) return normalizedRequestValue;

            return Environment.GetEnvironmentVariable(environmentVariableName)?.Trim();
        }
    }
}

#endif
