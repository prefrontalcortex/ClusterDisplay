using System.Collections;
using NUnit.Framework;
using Unity.ClusterDisplay.Graphics.Tests;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

/// <summary>
/// Same comparison as <see cref="TiledProjectionTest"/> but with point lights spread over the view: with the Forward+
/// rendering path, lights are assigned to screen tiles using the projection of the camera, which has been reported to
/// be wrong with custom projection matrices (which is what tiled projection uses).
/// </summary>
public class TiledProjectionPointLightsTest : ClusterRendererTest
{
    [OneTimeSetUp]
    public void LoadScene()
    {
        SceneManager.LoadScene("TiledProjection");
    }

    [UnityTest]
    public IEnumerator CompareVanillaAndStitchedClusterWithPointLights()
    {
        yield return RenderAndCompare(() =>
        {
            var camera = GraphicsTestUtil.FindUniqueMainCamera();
            Assert.That(camera, Is.Not.Null);

            // A grid of colored point lights in front of the camera, covering every tile of the cluster.
            var root = new GameObject("TestPointLights");
            var colors = new[] { Color.red, Color.green, Color.blue, Color.yellow, Color.cyan, Color.magenta };
            int index = 0;
            for (int y = -1; y <= 1; ++y)
            {
                for (int x = -2; x <= 2; ++x)
                {
                    var lightObject = new GameObject($"PointLight_{x}_{y}");
                    lightObject.transform.SetParent(root.transform, false);
                    lightObject.transform.position = camera.transform.position + camera.transform.rotation *
                        new Vector3(x * 2.5f, y * 1.5f, 5.0f);
                    var light = lightObject.AddComponent<Light>();
                    light.type = LightType.Point;
                    light.color = colors[index++ % colors.Length];
                    light.intensity = 40f;
                    light.range = 6f;
                }
            }
        });
    }
}
