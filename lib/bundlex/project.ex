defmodule Bundlex.Project do
  @moduledoc """
  Behaviour that should be implemented by each project using Bundlex in the
  `bundlex.exs` file.
  """
  use Bunch
  alias Bundlex.Helper.MixHelper
  alias __MODULE__.{Preprocessor, Store}

  @src_dir_name "c_src"
  @bundlex_file_name "bundlex.exs"

  @type native_name :: atom
  @type native_interface :: :nif | :cnode | :port
  @type native_language :: :c | :cpp

  @type os_dep_provider ::
          :pkg_config
          | {:pkg_config, pkg_configs :: String.t() | [String.t()]}
          | {:precompiled, url :: String.t()}
          | {:precompiled, url :: String.t(), libs :: String.t() | [String.t()]}

  @type os_dep :: {name :: atom, os_dep_provider | [os_dep_provider]}

  @typedoc """
  Type describing configuration of a native.

  Configuration of each native may contain following options:
  * `sources` - C files to be compiled (at least one must be provided).
  * `preprocessors` - Modules that will pre-process the native. They may change this configuration, for example
  by adding new keys. An example of preprocessor is [Unifex](https://hexdocs.pm/unifex/Unifex.html).
  See `Bundlex.Project.Preprocessor` for more details.
  * `interface` - Interface used to integrate with Elixir code. The following interfaces are available:
    * :nif - dynamically linked to the Erlang VM (see [Erlang docs](http://erlang.org/doc/man/erl_nif.html))
    * :cnode - executed as separate OS processes, accessed through sockets (see [Erlang docs](http://erlang.org/doc/man/ei_connect.html))
    * :port - executed as separate OS processes (see [Elixir Port docs](https://hexdocs.pm/elixir/Port.html))
  Specifying no interface is valid only for libs.
  * `deps` - Dependencies in the form of `{app, lib_name}`, where `app`
  is the application name of the dependency, and `lib_name` is the name of lib
  specified in Bundlex project of this dependency. Empty list by default. See _Dependencies_ section below
  for details.
  * `os_deps` - List of external OS dependencies. It's a keyword list, where each key is the
  dependency name and the value is a provider or a list of them. In the latter case, subsequent
  providers from the list will be tried until one of them succeeds. A provider may be one of:
    - `pkg_config` - Resolves the dependency via `pkg-config`. Can be either `{:pkg_config, pkg_configs}`
    or just `:pkg_config`, in which case the dependency name will be used as the pkg_config name.
    - `precompiled` - Downloads the dependency from a given url and sets appropriate compilation
    and linking flags. Can be either `{:precompiled, url, libs}` or `{:precompiled, url}`, in which
    case the dependency name will be used as the lib name.
    Precompiled dependencies for given applications (Mix projects) can be disabled via configuration, for example:

  ```elixir
    config :bundlex, :disable_precompiled_os_deps,
      apps: [:my_application, :another_application]
    ```

    Note that this will affect the natives and libs defined in the `bundlex.exs` files of specified
    applications only, not in their dependencies.

    Check `t:os_dep/0` for details.
  * `pkg_configs` - (deprecated, use `os_deps` instead) Names of libraries for which the appropriate flags will be
  obtained using pkg-config (empty list by default).
  * `language` - Language of native. `:c` or `:cpp` may be chosen (`:c` by default).
  * `src_base` - Native files should reside in `project_root/c_src/<src_base>`
  (application name by default).
  * `includes` - Paths to look for header files (empty list by default).
  * `lib_dirs` - Absolute paths to look for libraries (empty list by default).
  * `libs` - Names of libraries to link (empty list by default).
  * `compiler_flags` - Custom flags for compiler. Default `-std` flag for `:c` is `-std=c11` and for `:cpp` is `-std=c++17`.
  * `linker_flags` - Custom flags for linker.
  """

  native_config_type =
    quote do
      [
        sources: [String.t()],
        includes: [String.t()],
        lib_dirs: [String.t()],
        libs: [String.t()],
        os_deps: [os_dep],
        pkg_configs: [String.t()],
        deps: [{Application.app(), native_name | [native_name]}],
        src_base: String.t(),
        compiler_flags: [String.t()],
        linker_flags: [String.t()],
        language: :c | :cpp,
        interface: native_interface | [native_interface],
        preprocessor: [Preprocessor.t()] | Preprocessor.t()
      ]
    end

  @type native_config :: unquote(native_config_type)

  @spec native_config_keys :: [atom]
  def native_config_keys, do: unquote(Keyword.keys(native_config_type))

  @typedoc """
  Type describing input project configuration.

  It's a keyword list, where natives and libs can be specified. Libs are
  native packages that are compiled as static libraries and linked to natives
  that have them specified in `deps` field of their configuration.
  """
  @type config :: [{:natives | :libs, [{native_name, native_config}]}]

  @doc """
  Callback returning project configuration.
  """
  @callback project() :: config

  defmacro __using__(_args) do
    quote do
      @behaviour unquote(__MODULE__)
      @doc false
      @spec __bundlex_project__() :: true
      def __bundlex_project__, do: true

      @doc false
      @spec __src_path__() :: Path.t()
      def __src_path__, do: Path.join(__DIR__, unquote(@src_dir_name))
    end
  end

  @typedoc """
  Struct representing bundlex project.

  Contains the following fields:
  - `:config` - project configuration
  - `:src_path` - path to the native sources
  - `:module` - bundlex project module
  - `:app` - application that exports project
  """
  @type t :: %__MODULE__{
          config: config,
          src_path: String.t(),
          module: module,
          app: atom
        }

  @enforce_keys [:config, :src_path, :module, :app]
  defstruct @enforce_keys

  @doc """
  Determines if `module` is a bundlex project module.
  """
  @spec project_module?(module) :: boolean
  def project_module?(module) do
    function_exported?(module, :__bundlex_project__, 0) and module.__bundlex_project__()
  end

  @doc """
  Returns the project struct of given application.

  If the module has not been loaded yet, it is loaded from
  `project_dir/#{@bundlex_file_name}` file.
  """
  @spec get(application :: atom) ::
          {:ok, t}
          | {:error,
             :invalid_project_specification
             | {:no_bundlex_project_in_file, path :: binary()}
             | :unknown_application}
  def get(application \\ MixHelper.get_app!()) do
    project = Store.get_project(application)

    if project do
      {:ok, project}
    else
      with {:ok, module} <- load(application),
           {:ok, config} <- parse_project_config(module.project()) do
        project = %__MODULE__{
          config: config,
          src_path: module.__src_path__(),
          module: module,
          app: application
        }

        Store.store_project(application, project)
        {:ok, project}
      end
    end
  end

  @spec load(application :: atom) ::
          {:ok, module}
          | {:error, {:no_bundlex_project_in_file, path :: binary()} | :unknown_application}
  defp load(application) do
    with {:ok, dir} <- MixHelper.get_project_dir(application) do
      bundlex_file_path = dir |> Path.join(@bundlex_file_name)
      modules = Code.require_file(bundlex_file_path) |> Keyword.keys()

      modules
      |> Enum.find(&project_module?/1)
      |> Bunch.error_if_nil({:no_bundlex_project_in_file, bundlex_file_path})
    end
  end

  defp parse_project_config(config) do
    if Keyword.keyword?(config) do
      config =
        config
        |> delistify_interfaces(:libs)
        |> delistify_interfaces(:natives)

      {:ok, config}
    else
      {:error, :invalid_project_specification}
    end
  end

  defp delistify_interfaces(input_config, native_type) do
    natives = Keyword.get(input_config, native_type, [])

    natives =
      natives
      |> Enum.flat_map(fn {name, config} ->
        config
        |> Keyword.get(:interface, nil)
        |> Bunch.listify()
        |> Enum.map(&{name, Keyword.put(config, :interface, &1)})
      end)

    Keyword.put(input_config, native_type, natives)
  end
end
