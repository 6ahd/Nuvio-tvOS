import ProjectDescription

// Tuist root. It sits at the repository root so the project in tvos/ can use
// the AetherEngine package that prepare.sh fetches into vendor/.
let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: .all,
        generationOptions: .options(enforceExplicitDependencies: false)
    )
)
