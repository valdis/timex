defmodule Mix.Tasks.Tzdata do
  @usage """
  Usage: mix tzdata (clean [-f | --force] | rebuild | update)

  # Print this help
  mix tzdata

  # Clean timezone data files. Only removes database by defalt.
  # Force will remove the database **and** the Olson tzdata package.
  mix tzdata clean [-f | --force]

  # Rebuilds the database from the current Olson tzdata package.
  mix tzdata rebuild

  # First determines if there is a new Olson tzdata package, and
  # if so, downloads it and rebuilds the database with it.
  mix tzdata update
  """
  @shortdoc false
  @moduledoc """
  Downloads the tzdata from the IANA website, parses it
  into Elixir terms, and then stores the complete database
  in priv/tzdata/database.exs. During compilation, that
  database file is reified and compiled into function calls
  in the Timezone module, for performing timezone lookups and
  conversions.

  #{@usage}
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

  @ignored_files [
    "Makefile",      "README",
    "leapseconds",   "leapseconds.awk", "leap-seconds.list",
    "yearistype.sh", "iso3166.tab",
    "zone1970.tab",  "zone.tab",
    "factory"
  ]

  def run(args) do
    case args do
      ["clean"|flags] ->
        warn "Cleaning timezone data!"
        cond do
          "-f" in flags ->
            clean_tzdata!(true)
            clean_database!(true)
          "--force" in flags ->
            clean_tzdata!(true)
            clean_database!(true)
          true ->
            clean_database!(true)
        end
      ["rebuild"|_flags] ->
        info "Rebuilding timezone database..."
        case local_release do
          :not_found ->
            error "Cannot rebuild database. Olson tzdata sources not found!"
            exit(:normal)
          package_name ->
            Path.join(@tzdata_store, package_name) |> build!
        end
      ["update"|_] ->
        fetch_tzdata! |> build!
      _ ->
        IO.puts @usage
    end
  end

  defp build!({:ok, from}), do: build!(from)
  defp build!(from) do
    {:ok, from}
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
    client = case :ftp.open(@tzdata_host, options) do
      {:ok, client} -> client
      {:error, reason} ->
        error "Failed to connect to tzdata FTP: #{reason}"
        exit(:normal)
    end
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
      success "Download complete!"
      {:ok, download_path}
    end
    {:ok, download_path}
  end

  # Extracts tzdata in memory, and returns a Stream of {filename, binary_data} tuples
  defp extract_tzdata!({:ok, path}) do
    extracted = :erl_tar.extract('#{path}', [{:cwd, '#{@tzdata_store}'}, :compressed, :verbose, :memory])
    case extracted do
      {:ok, files} ->
        files
        |> Stream.map(fn {filename, bin} -> {List.to_string(filename), bin} end)
        |> Stream.filter(fn
          {filename, _} when filename in @ignored_files ->
            false
          {_, _} ->
            true
        end)
      {:error, reason} ->
        error "Failed to extract tzdata package: #{reason}"
        exit(:normal)
    end
  end

  defp parse_tzdata(data) do
    # TODO pass filename here
    case Parser.parse(data) do
      {:ok, db} -> db
      {:error, reason} ->
        error "Failed to parse tzata: #{reason}"
        exit(:normal)
      _ ->
        error "Failed to parse tzdata!"
    end
  end

  defp combine_parse_results(%Database{} = parse_result, %Database{} = combined) do
    Map.merge(parse_result, combined, fn 
      (:__struct__, m1, _m2) ->
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
    clean_database!
    error "Failed to compile timezone database: #{reason}"
  end

  defp clean_tzdata!(notify? \\ false) do
    if File.exists?(@tzdata_store) do
      File.ls!(@tzdata_store) |> Enum.each(&File.rm_rf!/1)
      if notify?, do: info("Olson tzdata package removed!")
    end
  end
  defp clean_database!(notify? \\ false) do
    if File.exists?(@tzdata_db) do
      File.rm_rf!(@tzdata_db)
      if notify?, do: info("Timezone database removed!")
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

  defp info(message),    do: print(message)
  defp success(message), do: print(message, IO.ANSI.green)
  defp warn(message),    do: print(message, IO.ANSI.yellow)
  defp error(message),   do: print(message, IO.ANSI.red)
  defp print(message, color \\ nil) do
    has_colors? = IO.ANSI.enabled?
    cond do
      color == nil -> message
      has_colors?  -> color <> message <> IO.ANSI.reset
      true         -> message
    end |> IO.puts
  end
end