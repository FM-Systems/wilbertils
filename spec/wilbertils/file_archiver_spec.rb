# require 'wilbertils/file_archiver'
# require 'aws-sdk-s3'

# RSpec.describe Wilbertils::FileArchiver do
#   before do
#     # Reset ENV variables before each test
#     allow(ENV).to receive(:[]).and_call_original
#   end

#   describe '.archive' do
#     let(:file_path) { '/tmp/test_file.txt' }
#     let(:upload_path) { 'some/upload/path/test_file.txt' }
#     let(:bucket_name) { 'mf-ftp-files' }
#     let(:environment_name) { 'production' }
#     let(:s3_resource) { instance_double(Aws::S3::Resource) }
#     let(:s3_bucket) { instance_double(Aws::S3::Bucket) }
#     let(:s3_object) { instance_double(Aws::S3::Object) }

#     before do
#       allow(described_class).to receive(:s3).and_return(s3_resource)
#       allow(s3_resource).to receive(:bucket).with(bucket_name).and_return(s3_bucket)
#       allow(s3_bucket).to receive(:object).and_return(s3_object)
#       allow(s3_object).to receive(:upload_file)
#       allow(File).to receive(:delete)
#       allow(ENV).to receive(:[]).with('AWS_REGION').and_return('us-east-1')
#       allow(ENV).to receive(:[]).with('ENVIRONMENT_NAME').and_return(environment_name)
#     end

#     context 'when no file with the same name exists' do
#       before do
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).and_return(false)
#       end

#       it 'uploads the file to S3 with the original path' do
#         expect(s3_bucket).to receive(:object).with("#{environment_name}/#{upload_path}")
#         expect(s3_object).to receive(:upload_file).with(file_path)
#         Wilbertils::FileArchiver.archive(file: file_path, upload_path: upload_path, bucket_name: bucket_name)
#       end

#       it 'deletes the local file if not in development environment' do
#         expect(File).to receive(:delete).with(file_path)
#         Wilbertils::FileArchiver.archive(file: file_path, upload_path: upload_path, bucket_name: bucket_name)
#       end

#       context 'when in development environment' do
#         let(:environment_name) { 'development' }

#         it 'does not delete the local file' do
#           expect(File).not_to receive(:delete)
#           Wilbertils::FileArchiver.archive(file: file_path, upload_path: upload_path, bucket_name: bucket_name)
#         end
#       end
#     end

#     context 'when files with the same name exist' do
#       before do
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with(upload_path).and_return(true)
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with("#{upload_path}-1").and_return(true)
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with("#{upload_path}-2").and_return(false)
#       end

#       it 'uploads the file with an incremented index' do
#         expect(s3_bucket).to receive(:object).with("#{environment_name}/#{upload_path}-2")
#         expect(s3_object).to receive(:upload_file).with(file_path)
#         Wilbertils::FileArchiver.archive(file: file_path, upload_path: upload_path, bucket_name: bucket_name)
#       end
#     end
#   end

#   describe '.get_file_index' do
#     let(:key) { 'some/path/file.txt' }

#     context 'when no file exists' do
#       before do
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).and_return(false)
#       end

#       it 'returns nil' do
#         expect(Wilbertils::FileArchiver.send(:get_file_index, key)).to be_nil
#       end
#     end

#     context 'when the original file exists but no indexed files exist' do
#       before do
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with(key).and_return(true)
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with("#{key}-1").and_return(false)
#       end

#       it 'returns 1' do
#         expect(Wilbertils::FileArchiver.send(:get_file_index, key)).to eq(1)
#       end
#     end

#     context 'when indexed files exist' do
#       before do
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with(key).and_return(true)
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with("#{key}-1").and_return(true)
#         allow(Wilbertils::FileArchiver).to receive(:object_exists?).with("#{key}-2").and_return(false)
#       end

#       it 'returns the next available index' do
#         expect(Wilbertils::FileArchiver.send(:get_file_index, key)).to eq(2)
#       end
#     end
#   end

#   describe '.object_exists?' do
#     let(:s3_resource) { instance_double(Aws::S3::Resource) }
#     let(:s3_bucket) { instance_double(Aws::S3::Bucket) }
#     let(:s3_object) { instance_double(Aws::S3::Object) }
#     let(:key) { 'some/key.txt' }
#     let(:bucket_name) { 'mf-ftp-files' }
#     let(:environment_name) { 'production' }

#     before do
#       allow(described_class).to receive(:s3).and_return(s3_resource)
#       allow(s3_resource).to receive(:bucket).with(bucket_name).and_return(s3_bucket)
#       allow(s3_bucket).to receive(:object).and_return(s3_object)
#       allow(ENV).to receive(:[]).with('AWS_REGION').and_return('us-east-1')
#       allow(ENV).to receive(:[]).with('ENVIRONMENT_NAME').and_return(environment_name)
#     end

#     context 'when object exists' do
#       before do
#         allow(s3_object).to receive(:exists?).and_return(true)
#       end

#       it 'returns true' do
#         expect(Wilbertils::FileArchiver.send(:object_exists?, key, bucket_name: bucket_name)).to be true
#       end
#     end

#     context 'when object does not exist' do
#       before do
#         allow(s3_object).to receive(:exists?).and_return(false)
#       end

#       it 'returns false' do
#         expect(Wilbertils::FileArchiver.send(:object_exists?, key, bucket_name: bucket_name)).to be false
#       end
#     end
#   end
# end 