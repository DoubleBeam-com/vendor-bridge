module VendorBridge
  module Transforms
    # Converts Google Drive "view" links into direct image URLs that downstream
    # systems (like POSaBIT's image importer) can actually fetch.
    #
    # Google Drive share links look like:
    #   https://drive.google.com/file/d/FILE_ID/view?usp=sharing
    #   https://drive.google.com/file/d/FILE_ID/view
    #   https://drive.google.com/open?id=FILE_ID
    #
    # These render a Drive preview page, not the image bytes. The direct form is:
    #   https://drive.usercontent.google.com/download?id=FILE_ID&export=view&authuser=0
    #
    # Non-Google-Drive URLs and nil/blank values are returned unchanged, so it's
    # safe to pipe every vendor image URL through `convert`.
    module GoogleDriveUrl
      DIRECT_URL = "https://drive.usercontent.google.com/download?id=%s&export=view&authuser=0".freeze

      # Matches: /file/d/<id>/view, /file/d/<id>, /d/<id>
      FILE_PATH_RE = %r{drive\.google\.com/(?:file/)?d/([A-Za-z0-9_-]+)}i

      # Matches: /open?id=<id> on drive.google.com
      QUERY_ID_RE = %r{drive\.google\.com/open\?[^#]*?\bid=([A-Za-z0-9_-]+)}i

      # Matches already-direct forms — both legacy (drive.google.com/uc?...id=) and
      # current (drive.usercontent.google.com/download?...id=).
      DOWNLOAD_QUERY_RE = %r{drive\.(?:usercontent\.)?google\.com/(?:uc|download)\?[^#]*?\bid=([A-Za-z0-9_-]+)}i

      # URLs whose path ends in a known image extension (before any query/fragment)
      # are already directly fetchable as images, so we leave them untouched even
      # if they happen to be on a Drive host.
      IMAGE_EXT_RE = /\.(?:jpg|jpeg|png|gif|webp|bmp|svg|tif|tiff|heic|heif|ico|avif)(?=[?#]|\z)/i

      module_function

      # Returns true when `url` is a Google Drive "view" style URL that needs
      # converting. Already-direct URLs and URLs that already point at an image
      # file (by extension) return false.
      def view_url?(url)
        return false unless url.is_a?(String)
        str = url.strip
        return false if str.empty?
        return false unless str.match?(/\Ahttps?:\/\//i)
        return false if image_extension?(str)
        return false unless str.include?("drive.google.com")
        return false if direct_url?(str)
        !!extract_file_id(str)
      end

      # Returns the direct image URL if `url` is a Google Drive view link;
      # otherwise returns `url` unchanged (including nil / non-strings).
      def convert(url)
        return url unless view_url?(url)
        id = extract_file_id(url.strip)
        format(DIRECT_URL, id)
      end

      # Extracts the Drive file id from any supported link shape.
      # Returns nil if no id can be found.
      def extract_file_id(url)
        return nil unless url.is_a?(String)
        if (m = url.match(FILE_PATH_RE))
          return m[1]
        end
        if (m = url.match(QUERY_ID_RE))
          return m[1]
        end
        if (m = url.match(DOWNLOAD_QUERY_RE))
          return m[1]
        end
        nil
      end

      def direct_url?(url)
        url.match?(DOWNLOAD_QUERY_RE)
      end

      def image_extension?(url)
        url.match?(IMAGE_EXT_RE)
      end
    end
  end
end
