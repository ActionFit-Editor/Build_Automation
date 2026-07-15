#if UNITY_EDITOR

using System.IO;
using NUnit.Framework;
using UnityEditor;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildSequenceTests
    {
        [TestCase(BuildTarget.Android, BuildRequestPlatform.Android, BuildRequestPlatform.iOS)]
        [TestCase(BuildTarget.iOS, BuildRequestPlatform.iOS, BuildRequestPlatform.Android)]
        [TestCase(BuildTarget.StandaloneOSX, BuildRequestPlatform.Android, BuildRequestPlatform.iOS)]
        public void BothStartsWithActiveMobileTarget(
            BuildTarget activeTarget,
            BuildRequestPlatform expectedFirst,
            BuildRequestPlatform expectedSecond)
        {
            bool resolved = CIBuildEntry.TryResolveBuildSequence(
                BuildRequestPlatform.Both,
                activeTarget,
                out BuildRequestPlatform first,
                out BuildRequestPlatform second);

            Assert.That(resolved, Is.True);
            Assert.That(first, Is.EqualTo(expectedFirst));
            Assert.That(second, Is.EqualTo(expectedSecond));
        }

        [TestCase(BuildRequestPlatform.Android)]
        [TestCase(BuildRequestPlatform.iOS)]
        public void SinglePlatformHasNoSecondBuild(BuildRequestPlatform requestedPlatform)
        {
            bool resolved = CIBuildEntry.TryResolveBuildSequence(
                requestedPlatform,
                BuildTarget.StandaloneOSX,
                out BuildRequestPlatform first,
                out BuildRequestPlatform second);

            Assert.That(resolved, Is.True);
            Assert.That(first, Is.EqualTo(requestedPlatform));
            Assert.That(second, Is.EqualTo(BuildRequestPlatform.None));
        }

        [Test]
        public void CurrentRequiresAnActiveMobileTarget()
        {
            bool resolved = CIBuildEntry.TryResolveBuildSequence(
                BuildRequestPlatform.Current,
                BuildTarget.StandaloneOSX,
                out _,
                out _);

            Assert.That(resolved, Is.False);
        }

        [Test]
        public void DevelopmentAndroidWorkingRequestUsesApkWithoutStoreUpload()
        {
            var request = new BuildRequest
            {
                platform = BuildRequestPlatform.Both,
                buildKind = BuildRequestKind.AndroidAabAndiOSXcodeProject,
                uploadTarget = BuildRequestUploadTarget.GooglePlayInternalAndTestFlight,
                developmentBuild = true,
                bundleNo = "555",
                iosBundleId = "com.actionfit.ios"
            };

            BuildRequestUtility.PrepareWorkingRequest(request, BuildRequestPlatform.Android);

            Assert.That(request.platform, Is.EqualTo(BuildRequestPlatform.Android));
            Assert.That(request.buildKind, Is.EqualTo(BuildRequestKind.AndroidApk));
            Assert.That(request.uploadTarget, Is.EqualTo(BuildRequestUploadTarget.None));
            Assert.That(request.bundleNo, Is.EqualTo("555"));
            Assert.That(request.developmentBuild, Is.True);
            Assert.That(request.iosBundleId, Is.Empty);
        }

        [Test]
        public void DevelopmentIosWorkingRequestUsesFixedTestFlightBuildNumber()
        {
            var request = new BuildRequest
            {
                platform = BuildRequestPlatform.Both,
                buildKind = BuildRequestKind.AndroidAabAndiOSXcodeProject,
                uploadTarget = BuildRequestUploadTarget.GooglePlayInternalAndTestFlight,
                developmentBuild = true,
                bundleNo = "555",
                androidPackageName = "com.actionfit.android",
                androidKeystoreFileName = "upload.keystore",
                androidKeystoreBase64 = "base64",
                androidKeystorePassword = "password",
                androidAliasPassword = "password",
                androidKeyaliasName = "upload"
            };

            BuildRequestUtility.PrepareWorkingRequest(request, BuildRequestPlatform.iOS);

            Assert.That(request.platform, Is.EqualTo(BuildRequestPlatform.iOS));
            Assert.That(request.buildKind, Is.EqualTo(BuildRequestKind.iOSXcodeProject));
            Assert.That(request.uploadTarget, Is.EqualTo(BuildRequestUploadTarget.TestFlight));
            Assert.That(request.bundleNo, Is.EqualTo("1"));
            Assert.That(request.developmentBuild, Is.True);
            Assert.That(request.androidPackageName, Is.Empty);
            Assert.That(request.androidKeystoreFileName, Is.Empty);
            Assert.That(request.androidKeystoreBase64, Is.Empty);
            Assert.That(request.androidKeystorePassword, Is.Empty);
            Assert.That(request.androidAliasPassword, Is.Empty);
            Assert.That(request.androidKeyaliasName, Is.Empty);
        }

        [Test]
        public void ReleaseWorkingRequestsPreserveStoreBehavior()
        {
            var androidRequest = new BuildRequest
            {
                platform = BuildRequestPlatform.Both,
                buildKind = BuildRequestKind.AndroidAabAndiOSXcodeProject,
                uploadTarget = BuildRequestUploadTarget.GooglePlayInternalAndTestFlight,
                developmentBuild = false,
                bundleNo = "555"
            };
            var iosRequest = new BuildRequest
            {
                platform = androidRequest.platform,
                buildKind = androidRequest.buildKind,
                uploadTarget = androidRequest.uploadTarget,
                developmentBuild = androidRequest.developmentBuild,
                bundleNo = androidRequest.bundleNo
            };

            BuildRequestUtility.PrepareWorkingRequest(androidRequest, BuildRequestPlatform.Android);
            BuildRequestUtility.PrepareWorkingRequest(iosRequest, BuildRequestPlatform.iOS);

            Assert.That(androidRequest.buildKind, Is.EqualTo(BuildRequestKind.AndroidAab));
            Assert.That(androidRequest.uploadTarget, Is.EqualTo(BuildRequestUploadTarget.GooglePlayInternalAndTestFlight));
            Assert.That(androidRequest.bundleNo, Is.EqualTo("555"));
            Assert.That(iosRequest.buildKind, Is.EqualTo(BuildRequestKind.iOSXcodeProject));
            Assert.That(iosRequest.uploadTarget, Is.EqualTo(BuildRequestUploadTarget.GooglePlayInternalAndTestFlight));
            Assert.That(iosRequest.bundleNo, Is.EqualTo("555"));
        }

        [Test]
        public void WorkingRequestPathAllowsOnlyFixedPlatformCopies()
        {
            string repositoryRoot = Path.Combine(Path.GetTempPath(), "build-automation-repository");
            string allowedPath = Path.Combine(repositoryRoot, BuildRequestUtility.AndroidWorkingRelativePath);

            bool valid = BuildRequestUtility.TryValidateWorkingRequestPath(
                repositoryRoot,
                allowedPath,
                false,
                out string validatedPath,
                out string error);

            Assert.That(valid, Is.True, error);
            Assert.That(validatedPath, Is.EqualTo(Path.GetFullPath(allowedPath)));
        }

        [TestCase(".build/build_request.json")]
        [TestCase(".build/ci/build_request_other.json")]
        [TestCase("../build_request_android.json")]
        public void WorkingRequestPathRejectsOriginalAndNonAllowlistedPaths(string relativePath)
        {
            string repositoryRoot = Path.Combine(Path.GetTempPath(), "build-automation-repository");

            bool valid = BuildRequestUtility.TryValidateWorkingRequestPath(
                repositoryRoot,
                relativePath,
                false,
                out _,
                out _);

            Assert.That(valid, Is.False);
        }
    }
}

#endif
