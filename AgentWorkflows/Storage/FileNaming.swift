import Foundation

func yamlFilename(for name: String) -> String {
    name.lowercased().replacing(" ", with: "-") + ".yaml"
}

/// Returns the package folder name for a workflow (yamlFilename without
/// the `.yaml` extension). User workflows live at
/// `.../workflows/{packageFolderName}/workflow.yaml`.
func packageFolderName(for workflowName: String) -> String {
    workflowName.lowercased().replacing(" ", with: "-")
}
