using Documenter, RecordIO

DocMeta.setdocmeta!(RecordIO, :DocTestSetup, :(using RecordIO); recursive = true)

makedocs(
    modules = [RecordIO],
    repo = Documenter.Remotes.GitHub("BioJulia", "RecordIO.jl"),
    sitename = "RecordIO.jl",
    doctest = true,
    pages = [
        "RecordIO" => "index.md",
        "Manual" => [
            "Record types" => "parsers.md",
            "Reading records" => "reading.md",
            "Writing records" => "writing.md",
            "Sources" => "sources.md",
            "Errors" => "errors.md",
        ],
        "Reference" => "reference.md",
    ],
    format = Documenter.HTML(edit_link = "develop"),
    authors = "Ciarán O'Mara",
    checkdocs = :public,
)

deploydocs(;
    repo = "github.com/BioJulia/RecordIO.jl.git",
    devbranch = "develop",
    push_preview = true,
    deps = nothing,
    make = nothing,
)
