#if CLUSTER_DISPLAY_URP
using System;
using System.Collections.Generic;

using UnityEditor.Build;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Unity.ClusterDisplay.Graphics.Editor
{
    class ShaderPreprocessor : IPreprocessShaders
    {
        public int callbackOrder => 0;

        public void OnProcessShader(Shader shader, ShaderSnippetData snippet, IList<ShaderCompilerData> data)
        {
            if (TryGetGlobalSettingsStripScreenCoordOverrideVariants(out var stripped) && stripped)
            {
                throw new InvalidOperationException(
                    "Screen Coordinates Override shader variants are stripped from Player builds. " +
                    "You can fix this by unselecting the \"Strip Screen Coord Override Variants\" checkbox " +
                    "in the Universal Render Pipeline Global Settings.");
            }
        }

        static bool TryGetGlobalSettingsStripScreenCoordOverrideVariants(out bool value)
        {
            if (GraphicsSettings.TryGetRenderPipelineSettings<URPShaderStrippingSetting>(out var strippingSettings))
            {
                value = strippingSettings.stripScreenCoordOverrideVariants;
                return true;
            }

            Debug.LogError("Could not read Universal Render Pipeline Global Settings.");
            value = true;
            return false;
        }
    }
}
#endif
