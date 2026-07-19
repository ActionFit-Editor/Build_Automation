#if UNITY_EDITOR

using System;
using System.Collections.Generic;
using ActionFit.SOSingleton;
using ActionFit.SOSingleton.Editor;
using UnityEditor;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    [CreateAssetMenu(fileName = "BuildAutomationSettings", menuName = "Build/BuildAutomationSettings")]
    [ActionFitSettingsAsset("BuildAutomation", ActionFitSettingsAssetLifetime.EditorOnly)]
    public class BuildAutomationSettingsSO : ScriptableObject
    {
        public const string SOPrefsKey = "LastUsedBuildAutomationSettings";
        public const string DefaultSettingsAssetPath = "Assets/_Data/_BuildAutomation/BuildAutomationSettingsSO.asset";

        public bool autoConfigureBuildSymbols = true;
        public List<SlackMentionEntry> buildCommitSlackMentions = new();

        [Serializable]
        public class SlackMentionEntry
        {
            public bool enabled = true;
            public string memberId = "";
            public string memo = "";
        }

        public static BuildAutomationSettingsSO FindSettingsAsset()
        {
            var saved = LoadAndRemember(EditorPrefs.GetString(SOPrefsKey, ""));
            if (saved != null) return saved;

            var result = ActionFitSettingsAssetProvider.Resolve(
                typeof(BuildAutomationSettingsSO), false);
            return LoadAndRemember(result.ActualPath);
        }

        public static BuildAutomationSettingsSO FindOrCreateSettingsAsset()
        {
            var settings = ActionFitSettingsAssetProvider.GetOrCreate<BuildAutomationSettingsSO>();
            return settings == null
                ? null
                : LoadAndRemember(AssetDatabase.GetAssetPath(settings));
        }

        private static BuildAutomationSettingsSO LoadAndRemember(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;

            var settings = AssetDatabase.LoadAssetAtPath<BuildAutomationSettingsSO>(path);
            if (settings != null)
                EditorPrefs.SetString(SOPrefsKey, path);

            return settings;
        }
    }
}

#endif
