# This file is a part of Julia. License is MIT: https://julialang.org/license

function temp_pkg_dir(fn::Function)
    local env_dir
    local old_load_path
    local old_depot_path
    local old_home_project
    local old_active_project
    local old_general_registry_url
    try
        old_load_path = copy(LOAD_PATH)
        old_depot_path = copy(DEPOT_PATH)
        old_home_project = Base.HOME_PROJECT[]
        old_active_project = Base.ACTIVE_PROJECT[]
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        Base.HOME_PROJECT[] = nothing
        Base.ACTIVE_PROJECT[] = nothing
        # Clone the registry only once
        old_general_registry_url = Pkg.Types.DEFAULT_REGISTRIES[1].url
        generaldir = joinpath(@__DIR__, "registries", "General")
        if !isdir(generaldir)
            mkpath(generaldir)
            Base.shred!(LibGit2.CachedCredentials()) do creds
                LibGit2.with(Pkg.GitTools.clone("https://github.com/JuliaRegistries/General.git",
                    generaldir, credentials = creds)) do repo
                end
            end
        end
        Pkg.Types.DEFAULT_REGISTRIES[1].url = generaldir
        withenv("JULIA_PROJECT" => nothing, "JULIA_LOAD_PATH" => nothing) do
            mktempdir() do env_dir
                mktempdir() do depot_dir
                    push!(LOAD_PATH, "@", "@v#.#", "@stdlib")
                    push!(DEPOT_PATH, depot_dir)
                    fn(env_dir)
                end
            end
        end
    finally
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        append!(LOAD_PATH, old_load_path)
        append!(DEPOT_PATH, old_depot_path)
        Base.HOME_PROJECT[] = old_home_project
        Base.ACTIVE_PROJECT[] = old_active_project
        Pkg.Types.DEFAULT_REGISTRIES[1].url = old_general_registry_url
    end
end

function cd_tempdir(f)
    mktempdir() do tmp
        cd(tmp) do
            f(tmp)
        end
    end
end

isinstalled(pkg) = Base.locate_package(Base.PkgId(pkg.uuid, pkg.name)) !== nothing

function write_build(path, content)
    build_filename = joinpath(path, "deps", "build.jl")
    mkpath(dirname(build_filename))
    write(build_filename, content)
end

function with_current_env(f)
    Pkg.activate(".")
    try
        f()
    finally
        Pkg.activate()
    end
end

function with_temp_env(f, env_name::AbstractString="Dummy")
    env_path = joinpath(mktempdir(), env_name)
    Pkg.generate(env_path)
    Pkg.activate(env_path)
    try
        applicable(f, env_path) ? f(env_path) : f()
    finally
        Pkg.activate()
    end
end

function with_pkg_env(fn::Function, path::AbstractString="."; change_dir=false)
    Pkg.activate(path)
    try
        if change_dir
            cd(fn, path)
        else
            fn()
        end
    finally
        Pkg.activate()
    end
end

import LibGit2
using UUIDs
const TEST_SIG = LibGit2.Signature("TEST", "TEST@TEST.COM", round(time()), 0)
const TEST_PKG = (name = "Example", uuid = UUID("7876af07-990d-54b4-ab0e-23690620f79a"))
