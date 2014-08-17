defmodule Mix.Tasks.Tzdata.Update do
  @shortdoc false
  @moduledoc """
  Downloads the tzdata from the IANA website, parses it
  into Elixir terms, and then stores the complete database
  in priv/tzdata/database.exs. During compilation, that
  database file is reified and compiled into function calls
  in the Timezone module, for performing timezone lookups and
  conversions.
  """
  use Mix.Task

  alias Timex.Parsers.Tzdata.Parser
  alias Timex.Parsers.Tzdata.Database

  @tzdata_host  'ftp.iana.org'
  @tzdata_dir   'tz'
  @tzdata_rels  'releases'
  @tzdata_file  'tzdata-latest.tar.gz'
  @tzdata_root  Path.join("priv", "tzdata") |> Path.expand
  @tzdata_store Path.join(@tzdata_root, "raw")
  @tzdata_db    Path.join(@tzdata_root, "database.exs")

  def run(_) do
    fetch_tzdata!
    |> extract_tzdata!
    |> Stream.map(fn {_, bin} -> parse_tzdata(bin) end)
    |> Enum.reduce(%Database{}, &combine_parse_results/2)
    |> persist_database!
    |> clean_up!
  end

  # Opens an FTP connection to the tzdata-latest.tar.gz package, and downloads it.
  defp fetch_tzdata! do
    info "Downloading tzdata from IANA ftp server..."
    # Prepare ftp client configuration
    options = [
      mode: :passive,
      verbose: :false,
      debug: :disable,
      ipfamily: :inet,
      timeout: 10_000, # ms
    ]
    # Connect to IANA ftp server
    {:ok, client} = :ftp.open(@tzdata_host, options)
    :ok = :ftp.user(client, 'anonymous', '')
    :ok = :ftp.type(client, :binary)
    :ok = :ftp.cd(client, @tzdata_dir)
    # Get the latest release version name from server
    latest_version = :ftp.ls(client, @tzdata_file) |> determine_release
    local_version  = local_release
    # Compare release versions to see if we need to pull a new version
    download? = case local_version do
      # Everything is accounted for, time to bail.
      ^latest_version ->
        if File.exists?(@tzdata_db) do
          success "Everything is up to date!"
          :ok = :ftp.close(client)
          exit(:normal)
        # Our local version is up to date, but we're missing the compiled database.
        else
          false
        end
      # We don't have a local version, pull the latest
      :not_found ->
        info "No tzdata package found. Downloading..."
        true
      # Our version is out of date, download new one
      _older_version ->
        info "Outdated tzdata package found. Downloading..."
        true
    end

    download_path = Path.join(@tzdata_store, latest_version)
    if download? do
      # Clear out old tzdata packages
      clean_tzdata!
      # Download latest
      :ok = :ftp.recv(client, @tzdata_file, '#{download_path}')
      :ok = :ftp.close(client)
      {:ok, download_path}
    end
    success "Raw tzdata package is up to date!"
    {:ok, download_path}
  end

  # Extracts tzdata in memory, and returns a Stream of {filename, binary_data} tuples
  defp extract_tzdata!({:ok, path}) do
    info "Extracting tzdata package to priv/tzdata/raw..."
    {:ok, files} = :erl_tar.extract('#{path}', [{:cwd, '#{@tzdata_store}'}, :compressed, :verbose, :memory])
    files
    |> Stream.map(fn {filename, bin} -> {List.to_string(filename), bin} end)
    |> Stream.filter(fn
      {"Makefile", _}          -> false
      {"README", _}            -> false
      {"leapseconds" <> _, _}  -> false
      {"leap-seconds.list", _} -> false
      {"yearistype.sh", _}     -> false
      {"iso3166.tab", _}       -> false
      {"zone1970.tab", _}      -> false
      {"zone.tab", _}          -> false
      {"factory", _}           -> false
      {filename, _}            -> true
    end)
  end

  defp parse_tzdata(data) do
    {:ok, db} = Parser.parse(data)
    db
  end

  defp combine_parse_results(%Database{} = parse_result, %Database{} = combined) do
    Map.merge(parse_result, combined, fn 
      (:__struct__, m1, m2) ->
        m1
      (_, adding, acc) when is_list(adding) and is_list(acc) ->
        adding ++ acc 
    end)
  end

  defp persist_database!(db) do
    Timex.Timezone.Database.persist!(db)
  end

  defp clean_up!(:ok) do
    success "Olson timezone database compiled successfully!"
  end
  defp clean_up!({:error, reason}) do
    error "Failed to compile timezone database: #{reason}"
  end

  defp clean_tzdata! do
    if File.exists?(@tzdata_store) do
      File.ls!(@tzdata_store) |> Enum.each(&File.rm_rf!/1)
    end
  end

  @tzdata_pattern ~r/(?<release>tzdata\d{4}\w+\.tar\.gz)/
  defp local_release do
    if File.exists?(@tzdata_store) do
      files = File.ls!(@tzdata_store)
      files |> Enum.find(:not_found, fn path ->
        Regex.match?(@tzdata_pattern, path)
      end)
    else
      File.mkdir_p!(@tzdata_store)
      :not_found
    end
  end

  defp determine_release({:ok, path}),
    do: path |> List.to_string |> determine_release
  defp determine_release(path) when is_binary(path) do
    if Regex.match?(@tzdata_pattern, path) do
      case Regex.named_captures(@tzdata_pattern, path) do
        %{"release" => release} -> release
        _ -> "tzdata-latest.tar.gz"
      end
    else
      # Return a default value, which will trigger a download of the latest relese
      "tzdata-latest.tar.gz"
    end
  end

  defp info(message),    do: IO.puts(message)
  defp success(message), do: IO.puts(IO.ANSI.green <> message <> IO.ANSI.reset)
  defp error(message),   do: IO.puts(IO.ANSI.red <> message <> IO.ANSI.reset)
end