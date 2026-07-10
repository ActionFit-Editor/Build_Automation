#if UNITY_EDITOR

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    [CreateAssetMenu(fileName = "BuildAutomationSettings", menuName = "Build/BuildAutomationSettings")]
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

            var defaultSettings = LoadAndRemember(DefaultSettingsAssetPath);
            if (defaultSettings != null) return defaultSettings;

            string[] guids = AssetDatabase.FindAssets("t:BuildAutomationSettingsSO");
            if (guids.Length == 0) return null;

            string path = guids
                .Select(AssetDatabase.GUIDToAssetPath)
                .OrderBy(p => p.StartsWith("Assets/", StringComparison.Ordinal) ? 0 : 1)
                .ThenBy(p => p, StringComparer.Ordinal)
                .FirstOrDefault();
            return LoadAndRemember(path);
        }

        public static BuildAutomationSettingsSO FindOrCreateSettingsAsset()
        {
            var settings = FindSettingsAsset();
            if (settings != null) return settings;

            EnsureFolder(Path.GetDirectoryName(DefaultSettingsAssetPath)?.Replace("\\", "/"));

            settings = CreateInstance<BuildAutomationSettingsSO>();
            AssetDatabase.CreateAsset(settings, DefaultSettingsAssetPath);
            EditorPrefs.SetString(SOPrefsKey, DefaultSettingsAssetPath);
            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();

            Debug.Log($"[BuildAutomation] BuildAutomationSettingsSO created: {DefaultSettingsAssetPath}");
            return settings;
        }

        private static BuildAutomationSettingsSO LoadAndRemember(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;

            var settings = AssetDatabase.LoadAssetAtPath<BuildAutomationSettingsSO>(path);
            if (settings != null)
                EditorPrefs.SetString(SOPrefsKey, path);

            return settings;
        }

        private static void EnsureFolder(string folder)
        {
            if (string.IsNullOrWhiteSpace(folder) || AssetDatabase.IsValidFolder(folder)) return;

            string parent = Path.GetDirectoryName(folder)?.Replace("\\", "/");
            if (!string.IsNullOrWhiteSpace(parent))
                EnsureFolder(parent);

            AssetDatabase.CreateFolder(parent, Path.GetFileName(folder));
        }
    }
}

#endif
