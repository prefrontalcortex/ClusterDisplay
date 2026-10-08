using System.Globalization;

namespace Unity.ClusterDisplay.MissionControl.LaunchCatalog
{
    /// <summary>
    /// Values exchanged with Unity and stored in LaunchCatalog.json / REST requests are always formatted with the
    /// invariant culture, they must be interpreted the same way no matter the culture of the machine running
    /// MissionControl (regression: with de-DE "42.28" was read as 4228).
    /// </summary>
    [SetCulture("de-DE")]
    [SetUICulture("de-DE")]
    public class CultureIndependenceTests
    {
        [Test]
        public void CultureIsGerman()
        {
            // Make sure this fixture really tests what it claims to test.
            Assert.That(CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator, Is.EqualTo(","));
        }

        [Test]
        public void FloatFromString()
        {
            LaunchParameter parameter = new() { Type = LaunchParameterType.Float };
            parameter.DefaultValue = "42.28";
            Assert.That(parameter.DefaultValue, Is.EqualTo(42.28f));
        }

        [Test]
        public void StringFromFloat()
        {
            LaunchParameter parameter = new() { Type = LaunchParameterType.String };
            parameter.DefaultValue = 42.28;
            Assert.That(parameter.DefaultValue, Is.EqualTo("42.28"));
        }

        [Test]
        public void RangeConstraintJsonRoundTrip()
        {
            RangeConstraint constraint = new() { Min = 0.5f, Max = 2.5f };
            var json = System.Text.Json.JsonSerializer.Serialize<Constraint>(constraint, Json.SerializerOptions);
            Assert.That(json, Does.Contain("0.5"));
            var deserialized = (RangeConstraint)System.Text.Json.JsonSerializer.Deserialize<Constraint>(json,
                Json.SerializerOptions)!;
            Assert.That(deserialized.MinSingle, Is.EqualTo(0.5f));
            Assert.That(deserialized.MaxSingle, Is.EqualTo(2.5f));
            Assert.That(deserialized.Validate(1.5f), Is.True);
            Assert.That(deserialized.Validate(3.5f), Is.False);
        }
    }
}
