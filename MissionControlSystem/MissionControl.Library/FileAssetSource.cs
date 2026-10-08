using System;
using System.Text.Json;
using Unity.ClusterDisplay.MissionControl.LaunchCatalog;

namespace Unity.ClusterDisplay.MissionControl.MissionControl.Library
{
    /// <summary>
    /// <see cref="IAssetSource"/> implementation that access the asset directly using the file system (on the computer
    /// running mission control).
    /// </summary>
    public class FileAssetSource : IAssetSource
    {
        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="assetRoot">Absolute path to the asset's root folder.</param>
        public FileAssetSource(string assetRoot)
        {
            m_AssetRoot = Path.GetFullPath(assetRoot);
            m_CatalogPath = Path.Combine(m_AssetRoot, "LaunchCatalog.json");
        }

        /// <inheritdoc/>
        public async Task<Catalog> GetCatalogAsync()
        {
            await using var loadStream = File.OpenRead(m_CatalogPath);
            Catalog? catalog;
            try
            {
                // Properties unknown to Catalog are silently ignored by the deserializer, so a catalog in an old
                // format would become an empty catalog (asset accepted, but nothing to launch).  Detect that by looking
                // for the two properties every catalog we produce has (even when empty).
                using (var document = await JsonDocument.ParseAsync(loadStream))
                {
                    if (document.RootElement.ValueKind != JsonValueKind.Object ||
                        !document.RootElement.EnumerateObject().Any(p =>
                            p.Name.Equals("payloads", StringComparison.OrdinalIgnoreCase) ||
                            p.Name.Equals("launchables", StringComparison.OrdinalIgnoreCase)))
                    {
                        throw new CatalogException($"{m_CatalogPath} has neither \"payloads\" nor \"launchables\", " +
                            $"it is most likely in an old (unsupported) format.");
                    }
                }
                loadStream.Position = 0;
                catalog = await JsonSerializer.DeserializeAsync<Catalog>(loadStream, Json.SerializerOptions);
            }
            catch (JsonException e)
            {
                throw new CatalogException($"Failed to parse {m_CatalogPath}: {e.Message}", e);
            }
            if (catalog == null)
            {
                throw new CatalogException($"Failed to deserialize content of {m_CatalogPath}");
            }
            return catalog;
        }

        /// <inheritdoc/>
        /// <exception cref="CatalogException">If <paramref name="path"/> is not located inside the asset's root
        /// folder.</exception>
        public Task<AssetSourceOpenedFile> GetFileContentAsync(string path)
        {
            string toOpenPath = GetPathInsideAsset(path);
            FileInfo toOpenInfo = new(toOpenPath);
            AssetSourceOpenedFile ret = new(File.OpenRead(toOpenPath), toOpenInfo.Length);
            ret.Stream.Position = 0;
            return Task.FromResult(ret);
        }

        /// <summary>
        /// Returns the absolute path of a file of the asset, making sure it stays inside of the asset's root folder
        /// (rejecting absolute paths and ".." escaping the folder).
        /// </summary>
        /// <param name="path">Path of the file relative to the asset's root folder.</param>
        /// <exception cref="CatalogException">If <paramref name="path"/> is not located inside the asset's root
        /// folder.</exception>
        string GetPathInsideAsset(string path)
        {
            string fullPath = Path.GetFullPath(path, m_AssetRoot);
            string rootWithSeparator = Path.EndsInDirectorySeparator(m_AssetRoot) ? m_AssetRoot :
                m_AssetRoot + Path.DirectorySeparatorChar;
            if (!fullPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
            {
                throw new CatalogException($"File path \"{path}\" in LaunchCatalog.json is not located inside of the " +
                    $"asset's folder.");
            }
            return fullPath;
        }

        /// <summary>
        /// Absolute path to the asset's root folder.
        /// </summary>
        readonly string m_AssetRoot;

        /// <summary>
        /// Absolute path to the asset's LaunchCatalog.json.
        /// </summary>
        readonly string m_CatalogPath;
    }
}
