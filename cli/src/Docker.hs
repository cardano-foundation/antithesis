module Docker
    ( build
    )
where

type CLI = (String, [String])

build
    :: FilePath -- Dockerfile path
    -> FilePath -- Context path
    -> String -- Tag
    -> String -- Label
    -> CLI
build dockerfile context tag label =
    ( "docker"
    ,
        [ "build"
        , "-f"
        , dockerfile
        , "-t"
        , tag
        , "--label"
        , label
        , context
        ]
    )
