module Wilbertils
  class FtpPaths
    class << self
      def create ftp_paths
        ftp_paths.each do |ftp_path|
          FileUtils.mkdir_p "#{ftp_path}/success" if Dir.glob("#{ftp_path}/success").empty?
          FileUtils.mkdir_p "#{ftp_path}/failure" if Dir.glob("#{ftp_path}/failure").empty?
        end
      end
    end
  end
end