# Règles PSScriptAnalyzer du kit.
# PSAvoidUsingWriteHost est exclue : l'affichage couleur à la console est voulu
# (le même texte est en parallèle écrit dans le journal).
@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
