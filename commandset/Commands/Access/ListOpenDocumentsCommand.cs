using Autodesk.Revit.UI;
using Newtonsoft.Json.Linq;
using RevitMCPCommandSet.Services;
using RevitMCPSDK.API.Base;
using System;

namespace RevitMCPCommandSet.Commands.Access
{
    public class ListOpenDocumentsCommand : ExternalEventCommandBase
    {
        private ListOpenDocumentsEventHandler _handler => (ListOpenDocumentsEventHandler)Handler;

        public override string CommandName => "list_open_documents";

        public ListOpenDocumentsCommand(UIApplication uiApp)
            : base(new ListOpenDocumentsEventHandler(), uiApp)
        {
        }

        public override object Execute(JObject parameters, string requestId)
        {
            if (RaiseAndWaitForCompletion(10000))
            {
                return _handler.ResultInfo;
            }

            throw new TimeoutException("list_open_documents timed out after 10000ms");
        }
    }
}
