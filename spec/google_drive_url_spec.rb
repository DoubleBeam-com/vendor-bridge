require_relative "spec_helper"
require_relative "../lib/transforms/google_drive_url"

RSpec.describe VendorBridge::Transforms::GoogleDriveUrl do
  describe ".convert" do
    it "rewrites the standard /file/d/<id>/view?usp=sharing share link" do
      url = "https://drive.google.com/file/d/1abcDEF_ghi-JKL123/view?usp=sharing"
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=1abcDEF_ghi-JKL123"
      )
    end

    it "rewrites /file/d/<id>/view without query params" do
      url = "https://drive.google.com/file/d/ABC123xyz_/view"
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=ABC123xyz_"
      )
    end

    it "rewrites /file/d/<id> without the trailing /view" do
      url = "https://drive.google.com/file/d/ABC123"
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=ABC123"
      )
    end

    it "rewrites /open?id=<id> links" do
      url = "https://drive.google.com/open?id=XYZ-789_id"
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=XYZ-789_id"
      )
    end

    it "accepts http as well as https" do
      url = "http://drive.google.com/file/d/foo/view?usp=sharing"
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=foo"
      )
    end

    it "leaves already-direct drive.usercontent.google.com/download URLs unchanged" do
      url = "https://drive.usercontent.google.com/download?id=abc123&export=view&authuser=0"
      expect(described_class.convert(url)).to eq(url)
    end

    it "leaves canonical /uc?export=view URLs unchanged (idempotent on rewritten data)" do
      url = "https://drive.google.com/uc?export=view&id=abc123"
      expect(described_class.convert(url)).to eq(url)
    end

    it "leaves non-Google-Drive URLs unchanged" do
      url = "https://pbit-production.s3.amazonaws.com/images/image/338643/foo.png"
      expect(described_class.convert(url)).to eq(url)
    end

    it "leaves URLs with image extensions unchanged" do
      expect(described_class.convert("https://example.com/path/photo.jpg")).to eq("https://example.com/path/photo.jpg")
      expect(described_class.convert("https://example.com/photo.PNG?w=300")).to eq("https://example.com/photo.PNG?w=300")
      expect(described_class.convert("https://drive.google.com/file/d/abc/preview.webp")).to eq("https://drive.google.com/file/d/abc/preview.webp")
    end

    it "returns nil unchanged" do
      expect(described_class.convert(nil)).to be_nil
    end

    it "returns an empty string unchanged" do
      expect(described_class.convert("")).to eq("")
    end

    it "returns non-URL strings unchanged" do
      expect(described_class.convert("not a url")).to eq("not a url")
    end

    it "returns non-string inputs unchanged" do
      expect(described_class.convert(42)).to eq(42)
    end

    it "trims whitespace before conversion" do
      url = "  https://drive.google.com/file/d/padded/view?usp=sharing  "
      expect(described_class.convert(url)).to eq(
        "https://drive.google.com/uc?export=view&id=padded"
      )
    end
  end

  describe ".view_url?" do
    it "is true for /file/d/<id>/view URLs" do
      expect(described_class.view_url?("https://drive.google.com/file/d/abc/view")).to be true
    end

    it "is true for /open?id=<id> URLs" do
      expect(described_class.view_url?("https://drive.google.com/open?id=abc")).to be true
    end

    it "is false for already-direct drive.usercontent.google.com/download URLs" do
      expect(described_class.view_url?("https://drive.usercontent.google.com/download?id=abc&export=view&authuser=0")).to be false
    end

    it "is false for canonical /uc?export=view URLs" do
      expect(described_class.view_url?("https://drive.google.com/uc?export=view&id=abc")).to be false
    end

    it "is false for non-Drive URLs" do
      expect(described_class.view_url?("https://example.com/image.png")).to be false
    end

    it "is false for URLs with image extensions" do
      expect(described_class.view_url?("https://drive.google.com/file/d/abc/photo.jpg")).to be false
    end

    it "is false for nil, empty, and non-string values" do
      expect(described_class.view_url?(nil)).to be false
      expect(described_class.view_url?("")).to be false
      expect(described_class.view_url?(42)).to be false
    end
  end

  describe ".apply_to_rows!" do
    it "rewrites _cover_image_url and stores the original in _old_cover_image_url for Drive view URLs" do
      rows = [{ "_cover_image_url" => "https://drive.google.com/file/d/abc123/view?usp=sharing" }]
      described_class.apply_to_rows!(rows)
      expect(rows.first["_cover_image_url"]).to eq("https://drive.google.com/uc?export=view&id=abc123")
      expect(rows.first["_old_cover_image_url"]).to eq("https://drive.google.com/file/d/abc123/view?usp=sharing")
    end

    it "leaves non-Drive URLs untouched and sets _old_cover_image_url to nil" do
      rows = [{ "_cover_image_url" => "https://cdn.example.com/foo.png" }]
      described_class.apply_to_rows!(rows)
      expect(rows.first["_cover_image_url"]).to eq("https://cdn.example.com/foo.png")
      expect(rows.first["_old_cover_image_url"]).to be_nil
    end

    it "handles nil cover URLs without raising" do
      rows = [{ "_cover_image_url" => nil }]
      described_class.apply_to_rows!(rows)
      expect(rows.first["_cover_image_url"]).to be_nil
      expect(rows.first["_old_cover_image_url"]).to be_nil
    end

    it "accepts custom source_field and audit_field" do
      rows = [{ "img" => "https://drive.google.com/file/d/xyz/view" }]
      described_class.apply_to_rows!(rows, source_field: "img", audit_field: "img_original")
      expect(rows.first["img"]).to eq("https://drive.google.com/uc?export=view&id=xyz")
      expect(rows.first["img_original"]).to eq("https://drive.google.com/file/d/xyz/view")
    end
  end
end
