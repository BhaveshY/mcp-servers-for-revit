using System.Collections.Generic;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace RevitMCPCommandSet.Utils
{
    /// <summary>
    /// Guards against running commands that need a graphical view while the user
    /// has a schedule, sheet, or similar non-graphical view active. Several
    /// Revit APIs (FilteredElementCollector(doc, viewId), View.SetElementOverrides,
    /// HideElements, IsolateElementsTemporary, dimension creation) require the
    /// active view to be one that actually draws geometry. They will throw or
    /// silently produce nothing on a schedule.
    /// </summary>
    public static class ActiveViewGuard
    {
        private static readonly HashSet<ViewType> GraphicalViewTypes = new HashSet<ViewType>
        {
            ViewType.FloorPlan,
            ViewType.CeilingPlan,
            ViewType.EngineeringPlan,
            ViewType.AreaPlan,
            ViewType.ThreeD,
            ViewType.Section,
            ViewType.Elevation,
            ViewType.Detail,
            ViewType.DraftingView,
            ViewType.Walkthrough,
            ViewType.Rendering
        };

        /// <summary>
        /// Returns true if the current active view supports geometry-based operations.
        /// On false, <paramref name="error"/> contains a user-facing message naming the
        /// actual view type so the caller can decide what to surface.
        /// </summary>
        public static bool RequireGraphicalView(UIDocument uidoc, out string error)
        {
            error = null;
            if (uidoc == null)
            {
                error = "No active Revit document. Open a project and try again.";
                return false;
            }
            var view = uidoc.ActiveView;
            if (view == null)
            {
                error = "No active view. Open a floor plan, section, elevation, or 3D view and try again.";
                return false;
            }
            if (!GraphicalViewTypes.Contains(view.ViewType))
            {
                error =
                    "This command requires a floor plan, section, elevation, or 3D view. " +
                    $"The active view is a {view.ViewType} (\"{view.Name}\"). " +
                    "Switch to a graphical view and try again.";
                return false;
            }
            return true;
        }
    }
}
