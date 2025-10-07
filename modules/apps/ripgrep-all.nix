{
  # rg, but also search in PDFs, E-Books, Office Documents, zip, tar.gz, and more
  ripgrep-all = {
    enable = false;
    custom_adapters = [
      {
        # The unique identifier and name of this adapter; must only include a-z, 0-9, _
        name = ""; # string

        # A description of this adapter; shown in rga's help
        description = ""; # string

        # If true, the adapter will be disabled by default
        disabled_by_default = false; # null or boolean

        # The path of the binary to run
        binary = ""; # absolute path

        # The output path hint; the placeholders are the same as for rga's args
        args = [ "" ]; # list of string

        # The file extensions this adapter supports
        extensions = [ "pdf" ]; # list of string

        # If not null and --rga-accurate is enabled, mime type matching is used instead of file name matching
        mimetypes = [ "application/pdf" ]; # null or (list of string)

        # if --rga-accurate, only match by mime types, ignore extensions completely
        match_only_by_mime = false; # null or boolean

        # The version identifier used to key cache entries; change if the configuration or program changes
        version = 1; # signed integer

        # Setting this is useful if the output format is not plain text (.txt but
        # instead some other format that should be passed to another adapter
        output_path_hint = ""; # null or string

      }

    ];

  };
}
