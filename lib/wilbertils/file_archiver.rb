module Wilbertils
  class FileArchiver
    
    class << self
      def archive file:, upload_path:, bucket_name: 'mf-ftp-files'        
        s3.bucket(bucket_name).object("#{ENV['ENVIRONMENT_NAME']}/#{upload_path}-#{Time.now.to_i}").upload_file(file)
        File.delete(file) unless ENV['ENVIRONMENT_NAME'].downcase == 'development'
      end
      
      private
      
      def s3
        @s3 ||= Aws::S3::Resource.new(region: ENV['AWS_REGION'])
      end
      
    end
  end
end