using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using RevitMCPSDK.API.Interfaces;
using System;
using System.Collections.Generic;
using System.Threading;

namespace RevitMCPCommandSet.Services
{
    public class ListOpenDocumentsEventHandler : IExternalEventHandler, IWaitableExternalEventHandler
    {
        public object ResultInfo { get; private set; }

        public bool TaskCompleted { get; private set; }
        private readonly ManualResetEvent _resetEvent = new ManualResetEvent(false);

        public bool WaitForCompletion(int timeoutMilliseconds = 10000)
        {
            _resetEvent.Reset();
            return _resetEvent.WaitOne(timeoutMilliseconds);
        }

        public void Execute(UIApplication app)
        {
            try
            {
                Document activeDocument = app.ActiveUIDocument?.Document;
                var documents = new List<object>();

                foreach (Document document in app.Application.Documents)
                {
                    documents.Add(new
                    {
                        title = document.Title,
                        pathName = document.PathName,
                        isActive = ReferenceEquals(document, activeDocument),
                        isFamilyDocument = document.IsFamilyDocument,
                        isWorkshared = document.IsWorkshared
                    });
                }

                ResultInfo = new
                {
                    count = documents.Count,
                    activeTitle = activeDocument?.Title,
                    documents
                };
            }
            catch (Exception ex)
            {
                ResultInfo = new
                {
                    count = 0,
                    activeTitle = (string)null,
                    documents = new object[0],
                    errorMessage = $"list_open_documents failed: {ex.Message}"
                };
            }
            finally
            {
                TaskCompleted = true;
                _resetEvent.Set();
            }
        }

        public string GetName()
        {
            return "List open documents";
        }
    }
}
