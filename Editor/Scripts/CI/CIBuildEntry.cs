#if UNITY_EDITOR

using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
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

        public static void SwitchToRequestBuildTarget()
        {
            int exitCode = ExecuteSwitchToRequestBuildTarget();
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

            if (!BuildSettingBridge.EnsureAvailable(false))
            {
                Debug.LogError("[CIBuildEntry] Build Setting package is required. Install/update Build Automation through ActionFit Package Manager so catalog dependencies are written to Packages/manifest.json, or manually add the Build Setting Git UPM URL before running CI.");
                return 1;
            }

            ScriptableObject settings = BuildSettingBridge.FindSettingsAsset();
            if (settings == null)
            {
                Debug.LogError("[CIBuildEntry] BuildSettingsSO not found");
                return 1;
            }

            ApplyRequest(settings, request);
            BuildSettingBridge.ApplyVersionSettings(settings);
            ApplyPlayerIdentifiers(settings);

            if (!ValidatePreparedBuildSymbols(request))
                return 1;

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

        private static void ApplyRequest(ScriptableObject settings, BuildRequest request)
        {
            string androidAlias = request.androidKeyaliasName?.Trim();
            string androidPackageName = request.androidPackageName?.Trim();
            string iosBundleId = request.iosBundleId?.Trim();
            string iosDevelopmentTeamId = Environment.GetEnvironmentVariable("IOS_DEVELOPMENT_TEAM_ID")?.Trim();

            if (!string.IsNullOrEmpty(request.buildVersion)) BuildSettingBridge.SetString(settings, "buildVersion", request.buildVersion);
            if (!string.IsNullOrEmpty(request.bundleNo)) BuildSettingBridge.SetString(settings, "bundleNo", request.bundleNo);
            if (!string.IsNullOrEmpty(request.buildFileName)) BuildSettingBridge.SetString(settings, "buildFileName", request.buildFileName);
            if (!string.IsNullOrEmpty(androidPackageName)) BuildSettingBridge.SetString(settings, "androidPackageName", androidPackageName);
            if (!string.IsNullOrEmpty(iosBundleId)) BuildSettingBridge.SetString(settings, "iosPackageName", iosBundleId);
            if (!string.IsNullOrEmpty(iosDevelopmentTeamId)) BuildSettingBridge.SetString(settings, "developmentTeamId", iosDevelopmentTeamId);
            if (!string.IsNullOrEmpty(androidAlias)) BuildSettingBridge.SetString(settings, "keyStoreAlias", androidAlias);
            BuildSettingBridge.SetBool(settings, "saveFileInProject", true);
            BuildSettingBridge.SetBool(settings, "manageSymbolsOnBuild", request.autoConfigureBuildSymbols);

            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CIBuildEntry] Request applied: trigger={request.triggerSource}, unityProjectPath={request.unityProjectPath}, platform={request.platform}, kind={request.buildKind}, upload={request.uploadTarget}, profile={request.distributionProfile}, autoConfigureBuildSymbols={request.autoConfigureBuildSymbols}, androidPackage={androidPackageName}, iosBundle={iosBundleId}, iosTeamId={iosDevelopmentTeamId}, androidAlias={androidAlias}");
        }

        private static void ApplyPlayerIdentifiers(ScriptableObject settings)
        {
            string androidPackageName = BuildSettingBridge.GetString(settings, "androidPackageName");
            string iosPackageName = BuildSettingBridge.GetString(settings, "iosPackageName");

            if (!string.IsNullOrWhiteSpace(androidPackageName))
                PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, androidPackageName.Trim());

            if (!string.IsNullOrWhiteSpace(iosPackageName))
                PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, iosPackageName.Trim());
        }

        private static BuildReport RunBuild(ScriptableObject settings, BuildRequest request)
        {
            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            Debug.Log(
                $"[CIBuildEntry] request platform={request.platform}, resolvedPlatform={platform}, " +
                $"activeBuildTarget={EditorUserBuildSettings.activeBuildTarget}, " +
                $"selectedGroup={EditorUserBuildSettings.selectedBuildTargetGroup}");

            switch (platform)
            {
                case BuildRequestPlatform.Android:
#if UNITY_ANDROID
                    ApplyAndroidSigning(request);
                    bool aab = request.buildKind != BuildRequestKind.AndroidApk;
                    return BuildSettingBridge.BuildAndroidForCI(settings, aab);
#else
                    Debug.LogError("[CIBuildEntry] Android build requested, but UNITY_ANDROID is not active. Run SwitchToRequestBuildTarget in a separate Unity batchmode step before BuildFromRequest.");
                    return null;
#endif
                case BuildRequestPlatform.iOS:
#if UNITY_IOS
                    return BuildSettingBridge.BuildIosForCI(settings);
#else
                    Debug.LogError("[CIBuildEntry] iOS build requested, but UNITY_IOS is not active. Run SwitchToRequestBuildTarget in a separate Unity batchmode step before BuildFromRequest.");
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

        private static int ExecuteSwitchToRequestBuildTarget()
        {
            BuildRequest request = BuildRequestUtility.Load();
            if (request == null) return 1;

            if (request.triggerSource != BuildRequest.BuildCommitTriggerSource)
            {
                Debug.LogError($"[CIBuildEntry] Unsupported trigger source: {request.triggerSource}");
                return 1;
            }

            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            if (!TryGetBuildTarget(platform, out BuildTargetGroup group, out BuildTarget target))
            {
                Debug.LogError($"[CIBuildEntry] Unsupported target switch platform: {platform}");
                return 1;
            }

            Debug.Log(
                $"[CIBuildEntry] target switch requested: requestPlatform={request.platform}, " +
                $"resolvedPlatform={platform}, target={target}, group={group}, " +
                $"activeBuildTarget={EditorUserBuildSettings.activeBuildTarget}, " +
                $"selectedGroup={EditorUserBuildSettings.selectedBuildTargetGroup}");

            if (request.autoConfigureBuildSymbols &&
                !CustomSymbolsBridge.TryApplyBuildSymbols(target, out string symbolError))
            {
                Debug.LogError($"[CIBuildEntry] {symbolError}");
                return 1;
            }

            if (EditorUserBuildSettings.activeBuildTarget == target)
            {
                Debug.Log($"[CIBuildEntry] Active build target is already {target}");
                return 0;
            }

            bool switched = EditorUserBuildSettings.SwitchActiveBuildTarget(group, target);
            if (!switched)
            {
                Debug.LogError($"[CIBuildEntry] Failed to switch active build target to {target}");
                return 1;
            }

            if (request.autoConfigureBuildSymbols &&
                !CustomSymbolsBridge.TryApplyBuildSymbols(target, out string postSwitchSymbolError))
            {
                Debug.LogError($"[CIBuildEntry] {postSwitchSymbolError}");
                return 1;
            }

            Debug.Log($"[CIBuildEntry] Switched active build target to {target}");
            return 0;
        }

        private static bool ValidatePreparedBuildSymbols(BuildRequest request)
        {
            if (!request.autoConfigureBuildSymbols)
            {
                Debug.Log("[CIBuildEntry] Automatic build symbol setup is disabled for this request");
                return true;
            }

            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            if (!TryGetBuildTarget(platform, out _, out BuildTarget target))
            {
                Debug.LogError($"[CIBuildEntry] Cannot validate Custom Symbols for platform: {platform}");
                return false;
            }

            if (!CustomSymbolsBridge.TryValidateBuildSymbols(target, out string error))
            {
                Debug.LogError($"[CIBuildEntry] {error}");
                return false;
            }

            return true;
        }

        private static bool TryGetBuildTarget(BuildRequestPlatform platform, out BuildTargetGroup group, out BuildTarget target)
        {
            switch (platform)
            {
                case BuildRequestPlatform.Android:
                    group = BuildTargetGroup.Android;
                    target = BuildTarget.Android;
                    return true;
                case BuildRequestPlatform.iOS:
                    group = BuildTargetGroup.iOS;
                    target = BuildTarget.iOS;
                    return true;
                default:
                    group = default;
                    target = default;
                    return false;
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
        private static void ApplyAndroidSigning(BuildRequest request)
        {
            string keystorePath = GetRequiredEnvironmentVariable("ANDROID_KEYSTORE_PATH");
            string keystorePass = GetRequiredEnvironmentVariable("ANDROID_KEYSTORE_PASS");
            string keyaliasPass = GetRequiredEnvironmentVariable("ANDROID_KEYALIAS_PASS");
            string aliasName = Environment.GetEnvironmentVariable("ANDROID_KEYALIAS_NAME")?.Trim();
            if (string.IsNullOrEmpty(aliasName)) aliasName = request.androidKeyaliasName?.Trim();
            bool hasAliasName = !string.IsNullOrEmpty(aliasName);

            PlayerSettings.Android.useCustomKeystore = true;
            if (!File.Exists(keystorePath))
                throw new FileNotFoundException("[CIBuildEntry] Android keystore file not found", keystorePath);

            PlayerSettings.Android.keystoreName = keystorePath;
            if (hasAliasName) PlayerSettings.Android.keyaliasName = aliasName;
            PlayerSettings.Android.keystorePass = keystorePass;
            PlayerSettings.Android.keyaliasPass = keyaliasPass;

            Debug.Log($"[CIBuildEntry] Android signing applied from runner-local secrets: alias={PlayerSettings.Android.keyaliasName}");
        }
#endif

        private static string GetRequiredEnvironmentVariable(string name)
        {
            string value = Environment.GetEnvironmentVariable(name)?.Trim();
            if (string.IsNullOrEmpty(value))
                throw new InvalidOperationException($"[CIBuildEntry] Required runner environment variable is missing: {name}");

            return value;
        }
    }
}

#endif
