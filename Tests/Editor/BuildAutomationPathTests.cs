#if UNITY_EDITOR

using NUnit.Framework;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildAutomationPathTests
    {
        [Test]
        public void RootUnityProjectUsesDotPath()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/repo",
                out string unityProjectPath,
                out string error);

            Assert.That(resolved, Is.True, error);
            Assert.That(unityProjectPath, Is.EqualTo("."));
        }

        [Test]
        public void NestedUnityProjectUsesRepositoryRelativePath()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/repo/KnitFactory",
                out string unityProjectPath,
                out string error);

            Assert.That(resolved, Is.True, error);
            Assert.That(unityProjectPath, Is.EqualTo("KnitFactory"));
        }

        [Test]
        public void UnityProjectOutsideRepositoryIsRejected()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/other/KnitFactory",
                out _,
                out string error);

            Assert.That(resolved, Is.False);
            Assert.That(error, Does.Contain("escapes the repository"));
        }

        [TestCase("../KnitFactory")]
        [TestCase("Games/../../KnitFactory")]
        [TestCase("/absolute/KnitFactory")]
        public void UnsafeUnityProjectPathIsRejected(string value)
        {
            bool normalized = BuildAutomationProjectPaths.TryNormalizeUnityProjectPath(
                value,
                out _,
                out _);

            Assert.That(normalized, Is.False);
        }
    }
}

#endif
