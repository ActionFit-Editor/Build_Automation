#if UNITY_EDITOR

using System;

namespace ActionFit.BuildAutomation.Editor
{
    public enum BuildRequestPlatform
    {
        Current = 0,
        Android = 1,
        iOS = 2,
        Both = 3
    }

    public enum BuildRequestKind
    {
        Default = 0,
        AndroidApk = 1,
        AndroidAab = 2,
        iOSXcodeProject = 3
    }

    public enum BuildRequestUploadTarget
    {
        None = 0,
        GooglePlayInternal = 1,
        TestFlight = 2,
        GooglePlayInternalAndTestFlight = 3
    }

    public enum BuildRequestDistributionProfile
    {
        Actionfit = 0,
        Stormborn = 1
    }

    [Serializable]
    public class BuildRequest
    {
        public const string BuildCommitTriggerSource = "BuildCommit";

        public int schemaVersion = 3;
        public string triggerSource = BuildCommitTriggerSource;
        public BuildRequestPlatform platform = BuildRequestPlatform.Current;
        public BuildRequestKind buildKind = BuildRequestKind.Default;
        public BuildRequestUploadTarget uploadTarget = BuildRequestUploadTarget.None;
        public BuildRequestDistributionProfile distributionProfile = BuildRequestDistributionProfile.Actionfit;
        public string buildVersion;
        public string bundleNo;
        public string buildFileName;
        public string androidPackageName;
        public string iosBundleId;
        public string androidKeyaliasName;
        public string sourceBranch;
        public string sourceCommit;
        public string createdAtUtc;
    }
}

#endif
