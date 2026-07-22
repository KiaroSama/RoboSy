@{
    # PSScriptAnalyzer settings for RoboSy.
    # RoboSy is an interactive console application (RoboSy.ps1 + lib/*.ps1), so a few
    # default rules are intentionally excluded to match the established project style.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # RoboSy is a console UI; Write-Host is used deliberately for colored output.
        'PSAvoidUsingWriteHost',
        # The custom Write-Log helper intentionally shadows nothing harmful at runtime.
        'PSAvoidOverwritingBuiltInCmdlets',
        # In-memory and interactive helpers do not need ShouldProcess support.
        'PSUseShouldProcessForStateChangingFunctions',
        # Established naming in this script (Normalize-*) predates this gate.
        'PSUseApprovedVerbs',
        # Several helpers return collections and read clearly with plural nouns.
        'PSUseSingularNouns',
        # Some catch blocks intentionally swallow errors to never break the UI flow.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
