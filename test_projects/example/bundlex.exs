defmodule Example.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives()
    ]
  end

  defp get_ffmpeg() do
    url =
      case Bundlex.get_target() do
        %{os: "linux"} ->
          "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n4.4-latest-linux64-gpl-shared-4.4.tar.xz/"

        %{architecture: "x86_64", os: "darwin" <> _rest_of_os_name} ->
          "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/latest/download/ffmpeg_macos_intel.tar.gz"

        _other ->
          nil
      end

    libs = ["libswscale", "libavcodec"]

    [{:precompiled, url, libs}, {:pkg_config, libs}]
  end

  defp natives do
    [
      example: [
        deps: [example_lib: :example_lib],
        src_base: "example",
        sources: ["foo_nif.c"],
        interface: [:nif],
        os_deps: [
          {:pkg_config, "libpng"}, # deprecated, testing for regression
          ffmpeg: get_ffmpeg(),
        ]
      ],
      example: [
        deps: [example_lib: :example_lib],
        src_base: "example",
        sources: ["example_cnode.c"],
        interface: [:cnode]
      ],
      example: [
        src_base: "example",
        sources: ["example_port.c"],
        interface: :port
      ]
    ]
  end
end
