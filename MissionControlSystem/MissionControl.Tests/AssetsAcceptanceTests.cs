using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Moq;
using Unity.ClusterDisplay.MissionControl.LaunchCatalog;
using Unity.ClusterDisplay.MissionControl.MissionControl.Library;

using static Unity.ClusterDisplay.MissionControl.MissionControl.Helpers;

namespace Unity.ClusterDisplay.MissionControl.MissionControl
{
    /// <summary>
    /// Tests of <see cref="AssetsManager"/> + <see cref="FileAssetSource"/> working together with real (not mocked)
    /// file blobs and payloads managers, on assets as they are produced by Unity (a folder with a LaunchCatalog.json).
    /// </summary>
    /// <remarks>Mostly regression tests for "asset produced by Unity is refused by MissionControl" problems.</remarks>
    public class AssetsAcceptanceTests
    {
        [SetUp]
        public void Setup()
        {
            m_FileBlobsManager = new FileBlobsManager(m_LoggerMock.Object);
            m_FileBlobsManager.AddStorageFolder(new StorageFolderConfig()
            {
                Path = NewTempFolder(),
                MaximumSize = 100 * 1024 * 1024
            });
            m_PayloadsManager = new PayloadsManager(m_LoggerMock.Object, NewTempFolder(), m_FileBlobsManager);
            m_AssetsManager = new AssetsManager(m_LoggerMock.Object, m_PayloadsManager, m_FileBlobsManager);
            m_AssetFolder = NewTempFolder();
        }

        [TearDown]
        public void TearDown()
        {
            foreach (string folder in m_TempFolders)
            {
                try
                {
                    Directory.Delete(folder, true);
                }
                catch
                {
                    // ignored
                }
            }
            m_TempFolders.Clear();
        }

        [Test]
        public async Task ValidAsset()
        {
            WriteAssetFile("Player.exe", "binary content");
            WriteAssetFile("Data/app.info", "line 1\nline 2\n");
            WriteCatalog(CreateCatalog("Player.exe", "Data/app.info"));

            var assetId = await AddAsset();

            using var lockedAssets = await m_AssetsManager.GetLockedReadOnlyAsync();
            Assert.That(lockedAssets.Value.Select(a => a.Key), Is.EquivalentTo(new[] { assetId }));
        }

        [Test]
        public async Task TextFileWithLineEndingsConverted()
        {
            // Catalog contains the MD5 of the file as produced by Unity (LF), but the copy we are asked to import
            // went through git with core.autocrlf=true (CRLF).
            const string producedByUnity = "line 1\nline 2\n";
            WriteAssetFile("Player.exe", "binary content");
            WriteAssetFile("Data/app.info", producedByUnity.Replace("\n", "\r\n"));
            WriteCatalog(CreateCatalog(
                ("Player.exe", "binary content"), ("Data/app.info", producedByUnity)));

            var exception = Assert.ThrowsAsync<CatalogException>(AddAsset);
            Assert.That(exception!.Message, Does.Contain("MD5 checksum mismatch"));
            Assert.That(exception.Message, Does.Contain("Data/app.info"), "Message should say which file is wrong");
            Assert.That(exception.Message, Does.Contain("line endings"));

            using var lockedAssets = await m_AssetsManager.GetLockedReadOnlyAsync();
            Assert.That(lockedAssets.Value, Is.Empty);
        }

        [Test]
        public void OldFormatCatalog()
        {
            // Format produced by older versions: deserializes without error, but without any payload or launchable.
            File.WriteAllText(Path.Combine(m_AssetFolder, "LaunchCatalog.json"),
                "{ \"name\": \"Player\", \"version\": \"1.0\", \"launchEntries\": [ { \"path\": \"Player.exe\" } ] }");
            WriteAssetFile("Player.exe", "binary content");

            var exception = Assert.ThrowsAsync<CatalogException>(AddAsset);
            Assert.That(exception!.Message, Does.Contain("old (unsupported) format"));
        }

        [Test]
        public void InvalidJsonCatalog()
        {
            File.WriteAllText(Path.Combine(m_AssetFolder, "LaunchCatalog.json"), "{ not json");

            var exception = Assert.ThrowsAsync<CatalogException>(AddAsset);
            Assert.That(exception!.Message, Does.Contain("LaunchCatalog.json"));
        }

        [Test]
        public void MissingCatalog()
        {
            // Asset produced without Mission Control integration activated: no LaunchCatalog.json (controller reports
            // IOException as not found).
            WriteAssetFile("Player.exe", "binary content");

            Assert.ThrowsAsync<FileNotFoundException>(AddAsset);
        }

        [Test]
        public void MissingFile()
        {
            WriteCatalog(CreateCatalog(("Player.exe", "binary content")));

            Assert.ThrowsAsync<FileNotFoundException>(AddAsset);
        }

        [TestCase("../outside.txt")]
        [TestCase("Data/../../outside.txt")]
        [TestCase("C:/Windows/win.ini")]
        [TestCase("/etc/passwd")]
        public async Task PathOutsideOfAssetFolder(string catalogPath)
        {
            File.WriteAllText(Path.Combine(m_AssetFolder, "..", "outside.txt"), "outside");
            WriteAssetFile("Player.exe", "binary content");
            WriteCatalog(CreateCatalog(("Player.exe", "binary content"), (catalogPath, "outside")));

            var exception = Assert.ThrowsAsync<CatalogException>(AddAsset);
            Assert.That(exception!.Message, Does.Contain("not located inside"));

            using var lockedAssets = await m_AssetsManager.GetLockedReadOnlyAsync();
            Assert.That(lockedAssets.Value, Is.Empty);
        }

        [Test]
        public void InvalidMd5String()
        {
            WriteAssetFile("Player.exe", "binary content");
            Catalog catalog = CreateCatalog(("Player.exe", "binary content"));
            catalog.Payloads = catalog.Payloads.Select(p => { p.Files = p.Files.Select(
                f => new LaunchCatalog.PayloadFile() { Path = f.Path, Md5 = "not-hexadecimal" }); return p; });
            WriteCatalog(catalog);

            var exception = Assert.ThrowsAsync<CatalogException>(AddAsset);
            Assert.That(exception!.Message, Does.Contain("Player.exe"));
        }

        /// <summary>
        /// Imports a real Unity build (folder containing a LaunchCatalog.json produced by the Mission Control
        /// postprocessor).  Only runs when the environment variable CLUSTERDISPLAY_TEST_ASSET is set to that folder.
        /// </summary>
        [Test]
        public async Task RealUnityBuild()
        {
            string? assetFolder = Environment.GetEnvironmentVariable("CLUSTERDISPLAY_TEST_ASSET");
            if (string.IsNullOrEmpty(assetFolder))
            {
                Assert.Ignore("CLUSTERDISPLAY_TEST_ASSET not set.");
            }

            AssetPost newAsset = new() { Name = "RealUnityBuild", Description = "Produced by Unity" };
            var assetId = await m_AssetsManager!.AddAssetAsync(newAsset, new FileAssetSource(assetFolder!));

            using var lockedAssets = await m_AssetsManager.GetLockedReadOnlyAsync();
            var asset = lockedAssets.Value[assetId];
            Assert.That(asset.Launchables.Select(l => l.Type), Is.EquivalentTo(new[] { "capcom", "clusterNode" }));
            Assert.That(asset.Launchables.All(l => l.Payloads.Any()), Is.True);
            Assert.That(asset.StorageSize, Is.GreaterThan(0));
        }

        Task<Guid> AddAsset()
        {
            AssetPost newAsset = new() { Name = "TestAsset", Description = "TestDescription" };
            return m_AssetsManager!.AddAssetAsync(newAsset, new FileAssetSource(m_AssetFolder));
        }

        /// <summary>
        /// Create a catalog referencing the specified files, with md5 computed from what is currently on disk.
        /// </summary>
        Catalog CreateCatalog(params string[] pathsOnDisk)
        {
            return CreateCatalog(pathsOnDisk.Select(p =>
                (p, File.ReadAllText(Path.Combine(m_AssetFolder, p)))).ToArray());
        }

        /// <summary>
        /// Create a catalog referencing the specified files, with md5 computed from the specified content.
        /// </summary>
        static Catalog CreateCatalog(params (string path, string content)[] files)
        {
            return new Catalog()
            {
                Payloads = new List<LaunchCatalog.Payload>()
                {
                    new()
                    {
                        Name = "Payload1",
                        Files = files.Select(f => new LaunchCatalog.PayloadFile()
                        {
                            Path = f.path,
                            Md5 = ComputeMd5String(Encoding.UTF8.GetBytes(f.content))
                        }).ToList()
                    }
                },
                Launchables = new List<LaunchCatalog.Launchable>()
                {
                    new()
                    {
                        Name = "Cluster Node",
                        Type = "clusterNode",
                        LaunchPath = "Player.exe",
                        Payloads = new [] { "Payload1" }
                    }
                }
            };
        }

        void WriteAssetFile(string path, string content)
        {
            string fullPath = Path.Combine(m_AssetFolder, path);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            File.WriteAllBytes(fullPath, Encoding.UTF8.GetBytes(content));
        }

        void WriteCatalog(Catalog catalog)
        {
            File.WriteAllText(Path.Combine(m_AssetFolder, "LaunchCatalog.json"),
                JsonSerializer.Serialize(catalog, Json.SerializerOptions));
        }

        string NewTempFolder()
        {
            // One level deeper so that "../outside.txt" tests stay in a folder we clean up.
            string root = Path.Combine(Path.GetTempPath(), "AssetsAcceptanceTests", Guid.NewGuid().ToString());
            string folder = Path.Combine(root, "asset");
            Directory.CreateDirectory(folder);
            m_TempFolders.Add(root);
            return folder;
        }

        readonly Mock<ILogger> m_LoggerMock = new();
        readonly List<string> m_TempFolders = new();
        FileBlobsManager? m_FileBlobsManager;
        PayloadsManager? m_PayloadsManager;
        AssetsManager? m_AssetsManager;
        string m_AssetFolder = "";
    }
}
