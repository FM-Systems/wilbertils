module Wilbertils
  class FileArchiver
    class << self
      def archive file:, upload_path:, bucket_name: 'mf-ftp-files'
        object = s3.bucket(bucket_name).object("#{ENV['ENVIRONMENT_NAME']}/#{upload_path}-#{Time.now.to_i}")
        transport_manager.upload_file(file, bucket: object.bucket_name, key: object.key)
        File.delete(file) unless ENV['ENVIRONMENT_NAME'].downcase == 'development'
      end

      private

      def s3
        @s3 ||= Aws::S3::Resource.new(region: ENV['AWS_REGION'])
      end

      def transport_manager
        @tm ||= Aws::S3::TransferManager.new(client: s3.client)
      end
    end
  end
end