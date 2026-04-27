using Autodesk.Revit.DB;

namespace RevitMCPCommandSet.Utils
{
    /// <summary>
    /// Extension methods for ElementId that paper over Revit API version differences.
    /// </summary>
    /// <remarks>
    /// Revit API ElementId numeric accessor by version:
    ///   R20–R23: <c>ElementId.IntegerValue</c> (int)
    ///   R24:     <c>ElementId.Value</c> (long)
    ///   R25+:    <c>ElementId.GetValue()</c> (long) — <c>.Value</c> still exists but is deprecated
    /// Call <see cref="GetIdValue"/> from version-agnostic code.
    /// </remarks>
    public static class ElementIdExtensions
    {
        /// <summary>
        /// Returns the numeric value of an <see cref="ElementId"/> as <see cref="long"/>,
        /// portably across Revit 2020 through 2026+.
        /// </summary>
        public static long GetIdValue(this ElementId id)
        {
#if REVIT2025_OR_GREATER
            return id.GetValue();
#elif REVIT2024_OR_GREATER
            return id.Value;
#else
            return id.IntegerValue;
#endif
        }

        /// <summary>
        /// Returns the numeric value of an <see cref="ElementId"/> as <see cref="int"/>.
        /// Use only for serialization to schemas that already store an int.
        /// </summary>
        public static int GetIntIdValue(this ElementId id)
        {
#if REVIT2024_OR_GREATER
            return (int)id.GetIdValue();
#else
            return id.IntegerValue;
#endif
        }

        /// <summary>
        /// Back-compat alias for callers that already use <c>GetValue()</c>.
        /// On Revit 2025+, the real <c>ElementId.GetValue()</c> instance method takes priority
        /// over this extension, so behaviour is identical there.
        /// Prefer <see cref="GetIdValue"/> in new code.
        /// </summary>
        public static long GetValue(this ElementId id) => id.GetIdValue();

        /// <summary>Back-compat alias. Prefer <see cref="GetIntIdValue"/>.</summary>
        public static int GetIntValue(this ElementId id) => id.GetIntIdValue();
    }
}
