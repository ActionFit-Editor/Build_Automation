#if UNITY_EDITOR

using System;
using System.Reflection;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    internal static class BuildSettingBridge
    {
        internal const string PackageId = "com.actionfit.buildsetting";
        internal const string MinimumVersion = "1.1.3";
        internal const string BuildSettingsTypeName = "ActionFit.BuildSetting.Editor.BuildSettingsSO, com.actionfit.buildsetting.Editor";

        private const string BuildSettingsApplierTypeName = "ActionFit.BuildSetting.Editor.BuildSettingsApplier, com.actionfit.buildsetting.Editor";
        private const string AndroidBuildProcessTypeName = "ActionFit.BuildSetting.Editor.AOSBuildProcess, com.actionfit.buildsetting.Editor";
        private const string IosBuildProcessTypeName = "ActionFit.BuildSetting.Editor.iOSBuildProcess, com.actionfit.buildsetting.Editor";
        private const string FallbackSOPrefsKey = "LastUsedBuildSettings";

        internal static Type SettingsType => Type.GetType(BuildSettingsTypeName);

        internal static string SOPrefsKey
        {
            get
            {
                FieldInfo field = SettingsType?.GetField("SOPrefsKey", BindingFlags.Public | BindingFlags.Static);
                return field?.GetValue(null) as string ?? FallbackSOPrefsKey;
            }
        }

        internal static bool IsAvailable()
        {
            return SettingsType != null;
        }

        internal static bool EnsureAvailable(bool showDialog)
        {
            if (IsAvailable())
                return true;

            if (showDialog)
            {
                EditorUtility.DisplayDialog(
                    "Build Setting Required",
                    $"Build Automation requires `{PackageId}@{MinimumVersion}`.\n\n" +
                    "Install or update Build Automation through ActionFit Package Manager so catalog dependencies are written to the project manifest, then reopen Unity after Package Manager resolves.",
                    "OK");
            }

            return false;
        }

        internal static ScriptableObject FindSettingsAsset()
        {
            return InvokeStaticSettingsMethod("FindSettingsAsset") as ScriptableObject;
        }

        internal static ScriptableObject FindOrCreateSettingsAsset()
        {
            return InvokeStaticSettingsMethod("FindOrCreateSettingsAsset") as ScriptableObject;
        }

        internal static void ApplyVersionSettings(ScriptableObject settings)
        {
            Type type = Type.GetType(BuildSettingsApplierTypeName);
            MethodInfo method = type?.GetMethod("ApplyVersionSettings", BindingFlags.Public | BindingFlags.Static);
            method?.Invoke(null, new object[] { settings });
        }

        internal static BuildReport BuildAndroidForCI(ScriptableObject settings, bool aab)
        {
            Type type = Type.GetType(AndroidBuildProcessTypeName);
            MethodInfo method = type?.GetMethod("BuildForCI", BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, new object[] { settings, aab }) as BuildReport;
        }

        internal static BuildReport BuildIosForCI(ScriptableObject settings)
        {
            Type type = Type.GetType(IosBuildProcessTypeName);
            MethodInfo method = type?.GetMethod("BuildForCI", BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, new object[] { settings }) as BuildReport;
        }

        internal static string GetString(ScriptableObject settings, string fieldName)
        {
            object value = GetFieldValue(settings, fieldName);
            return value as string ?? "";
        }

        internal static void SetString(ScriptableObject settings, string fieldName, string value)
        {
            SetFieldValue(settings, fieldName, value ?? "");
        }

        internal static void SetBool(ScriptableObject settings, string fieldName, bool value)
        {
            SetFieldValue(settings, fieldName, value);
        }

        private static object InvokeStaticSettingsMethod(string methodName)
        {
            Type type = SettingsType;
            MethodInfo method = type?.GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, null);
        }

        private static object GetFieldValue(ScriptableObject settings, string fieldName)
        {
            if (settings == null || string.IsNullOrEmpty(fieldName))
                return null;

            FieldInfo field = settings.GetType().GetField(fieldName, BindingFlags.Public | BindingFlags.Instance);
            return field?.GetValue(settings);
        }

        private static void SetFieldValue(ScriptableObject settings, string fieldName, object value)
        {
            if (settings == null || string.IsNullOrEmpty(fieldName))
                return;

            FieldInfo field = settings.GetType().GetField(fieldName, BindingFlags.Public | BindingFlags.Instance);
            field?.SetValue(settings, value);
        }
    }
}

#endif
