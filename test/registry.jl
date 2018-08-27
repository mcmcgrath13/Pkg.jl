module RegistryTests

using Pkg, UUIDs, LibGit2, Test
using Pkg: depots1
using Pkg.REPLMode: pkgstr
using Pkg.Types: PkgError

include("utils.jl")

const TEST_SIG = LibGit2.Signature("TEST", "TEST@TEST.COM", round(time()), 0)


function setup_test_registries(dir = pwd())
    # Set up two registries with the same name, with different uuid
    pkg_uuids = ["c5f1542f-b8aa-45da-ab42-05303d706c66", "d7897d3a-8e65-4b65-bdc8-28ce4e859565"]
    reg_uuids = ["e9fceed0-5623-4384-aff0-6db4c442647a", "a8e078ad-b4bd-4e09-a52f-c464826eef9d"]
    for i in 1:2
        regpath = joinpath(dir, "RegistryFoo$(i)")
        mkpath(joinpath(regpath, "Example"))
        write(joinpath(regpath, "Registry.toml"), """
            name = "RegistryFoo"
            uuid = "$(reg_uuids[i])"
            repo = "https://github.com"
            [packages]
            $(pkg_uuids[i]) = { name = "Example$(i)", path = "Example" }
            """)
        write(joinpath(regpath, "Example", "Package.toml"), """
            name = "Example$(i)"
            uuid = "$(pkg_uuids[i])"
            repo = "https://github.com/JuliaLang/Example.jl.git"
            """)
        write(joinpath(regpath, "Example", "Versions.toml"), """
            ["0.5.1"]
            git-tree-sha1 = "8eb7b4d4ca487caade9ba3e85932e28ce6d6e1f8"
            """)
        write(joinpath(regpath, "Example", "Deps.toml"), """
            ["0.5"]
            julia = "0.6-1.0"
            """)
        write(joinpath(regpath, "Example", "Compat.toml"), """
            ["0.5"]
            julia = "0.6-1.0"
            """)
        LibGit2.with(LibGit2.init(regpath)) do repo
            LibGit2.add!(repo, "*")
            LibGit2.commit(repo, "initial commit"; author=TEST_SIG, committer=TEST_SIG)
        end
    end
end

function test_installed(registries)
    @test setdiff(
        UUID[r.uuid for r in registries],
        UUID[r.uuid for r in Pkg.Types.collect_registries(;clone_default=false)]
        ) == UUID[]
end

function is_pkg_available(pkg::PackageSpec)
    uuids = UUID[]
    for registry in Pkg.Types.collect_registries(;clone_default=false)
        reg_dict = Pkg.Types.read_registry(joinpath(registry.path, "Registry.toml"))
        for (uuid, pkginfo) in reg_dict["packages"]
            push!(uuids, UUID(uuid))
        end
    end
    return in(pkg.uuid, uuids)
end


@testset "registries" begin
    temp_pkg_dir() do depot
        # set up registries
        regdir = mktempdir()
        setup_test_registries(regdir)
        generalurl = Pkg.Types.DEFAULT_REGISTRIES[1].url # hehe
        General = RegistrySpec(name = "General", uuid = "23338594-aafe-5451-b93e-139f81909106",
            url = generalurl)
        Foo1 = RegistrySpec(name = "RegistryFoo", uuid = "e9fceed0-5623-4384-aff0-6db4c442647a",
            url = joinpath(regdir, "RegistryFoo1"))
        Foo2 = RegistrySpec(name = "RegistryFoo", uuid = "a8e078ad-b4bd-4e09-a52f-c464826eef9d",
            url = joinpath(regdir, "RegistryFoo2"))

        # Packages in registries
        Example  = PackageSpec(name = "Example",  uuid = "7876af07-990d-54b4-ab0e-23690620f79a")
        Example1 = PackageSpec(name = "Example1", uuid = "c5f1542f-b8aa-45da-ab42-05303d706c66")
        Example2 = PackageSpec(name = "Example2", uuid = "d7897d3a-8e65-4b65-bdc8-28ce4e859565")


        # Add General registry
        ## Pkg REPL
        for reg in ("General",
                    "23338594-aafe-5451-b93e-139f81909106",
                    "General=23338594-aafe-5451-b93e-139f81909106")
            pkgstr("registry add $(reg)")
            test_installed([General])

            pkgstr("registry up $(reg)")
            test_installed([General])
            pkgstr("registry rm $(reg)")
            test_installed([])
        end
        ## Pkg.Registry API
        for reg in ("General",
                    RegistrySpec("General"),
                    RegistrySpec(name = "General"),
                    RegistrySpec(name = "General", url = generalurl),
                    RegistrySpec(uuid = "23338594-aafe-5451-b93e-139f81909106"),
                    RegistrySpec(name = "General", uuid = "23338594-aafe-5451-b93e-139f81909106"))
            Pkg.Registry.add(reg)
            test_installed([General])
            @test is_pkg_available(Example)
            Pkg.Registry.up(reg)
            test_installed([General])
            Pkg.Registry.rm(reg)
            test_installed([])
            @test !is_pkg_available(Example)
        end

        # Add registry from URL/local path.
        pkgstr("registry add $(Foo1.url)")
        test_installed([Foo1])
        @test is_pkg_available(Example1)
        @test !is_pkg_available(Example2)
        pkgstr("registry add $(Foo2.url)")
        test_installed([Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)

        # reset installed registries
        rm(joinpath(depots1(), "registries"); force=true, recursive=true)

        Pkg.Registry.add(RegistrySpec(url = Foo1.url))
        test_installed([Foo1])
        @test is_pkg_available(Example1)
        @test !is_pkg_available(Example2)
        Pkg.Registry.add(RegistrySpec(url = Foo2.url))
        test_installed([Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)

        # Behaviour with conflicting registry names
        @test_throws PkgError pkgstr("registry up RegistryFoo")
        @test_throws PkgError Pkg.Registry.up("RegistryFoo")
        @test_throws PkgError Pkg.Registry.up(RegistrySpec("RegistryFoo"))
        @test_throws PkgError Pkg.Registry.up(RegistrySpec(name = "RegistryFoo"))
        @test_throws PkgError pkgstr("registry remove RegistryFoo")
        @test_throws PkgError Pkg.Registry.rm("RegistryFoo")
        @test_throws PkgError Pkg.Registry.rm(RegistrySpec("RegistryFoo"))
        @test_throws PkgError Pkg.Registry.rm(RegistrySpec(name = "RegistryFoo"))

        pkgstr("registry up $(Foo1.uuid)")
        pkgstr("registry update $(Foo1.name)=$(Foo1.uuid)")
        Pkg.Registry.up(RegistrySpec(uuid = Foo1.uuid))
        Pkg.Registry.up(RegistrySpec(name = Foo1.name, uuid = Foo1.uuid))

        test_installed([Foo1, Foo2])
        pkgstr("registry rm $(Foo1.uuid)")
        test_installed([Foo2])
        @test !is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.add(RegistrySpec(url = Foo1.url))
        test_installed([Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        pkgstr("registry rm $(Foo1.name)=$(Foo1.uuid)")
        test_installed([Foo2])
        @test !is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        pkgstr("registry rm $(Foo2.name)")
        test_installed([])
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example2)

        Pkg.Registry.add(RegistrySpec(url = Foo1.url))
        Pkg.Registry.add(RegistrySpec(url = Foo2.url))
        test_installed([Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.rm(RegistrySpec(uuid = Foo1.uuid))
        test_installed([Foo2])
        @test !is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.add(RegistrySpec(url = Foo1.url))
        test_installed([Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.rm(RegistrySpec(name = Foo1.name, uuid = Foo1.uuid))
        test_installed([Foo2])
        @test !is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.rm(RegistrySpec(Foo2.name))
        test_installed([])
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example2)

        # multiple registries on the same time
        pkgstr("registry add General $(Foo1.url) $(Foo2.url)")
        test_installed([General, Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        pkgstr("registry up General $(Foo1.uuid) $(Foo2.name)=$(Foo2.uuid)")
        pkgstr("registry rm General $(Foo1.uuid) $(Foo2.name)=$(Foo2.uuid)")
        test_installed([])
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example2)

        Pkg.Registry.add([RegistrySpec("General"),
                          RegistrySpec(url = Foo1.url),
                          RegistrySpec(url = Foo2.url)])
        test_installed([General, Foo1, Foo2])
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example1)
        @test is_pkg_available(Example2)
        Pkg.Registry.up([RegistrySpec("General"),
                         RegistrySpec(uuid = Foo1.uuid),
                         RegistrySpec(name = Foo2.name, uuid = Foo2.uuid)])
        Pkg.Registry.rm([RegistrySpec("General"),
                         RegistrySpec(uuid = Foo1.uuid),
                         RegistrySpec(name = Foo2.name, uuid = Foo2.uuid)])
        test_installed([])
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example1)
        @test !is_pkg_available(Example2)

    end
end

end # module
