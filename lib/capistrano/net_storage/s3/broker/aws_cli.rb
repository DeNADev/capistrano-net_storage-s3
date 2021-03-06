require 'json'
require 'time'
require 'retryable'

require 'capistrano/net_storage/s3/base'
require 'capistrano/net_storage/s3/broker/base'

class Capistrano::NetStorage::S3::Broker::AwsCLI < Capistrano::NetStorage::S3::Broker::Base
  def check
    execute_aws_s3('ls', config.bucket_url)
  end

  def find_uploaded
    if capture_aws_s3('ls', config.archive_url)
      set :net_storage_uploaded_archive, true
    end
  rescue SSHKit::StandardError
    c = config
    run_locally do
      info "Archive is not found as #{c.archive_url}"
    end
  end

  def upload
    c  = config
    ns = net_storage
    Retryable.retryable(tries: c.max_retry, sleep: 0.1) do
      execute_aws_s3('cp', ns.local_archive_path, c.archive_url)
    end
  end

  def download
    c  = config
    ns = net_storage
    on ns.servers, in: :groups, limit: ns.max_parallels do
      Retryable.retryable(tries: c.max_retry, sleep: 0.1) do
        within releases_path do
          with(c.aws_environments) do
            execute :aws, 's3', 'cp', c.archive_url, ns.archive_path
          end
        end
      end
    end
  end

  def cleanup
    c         = config
    list_args = %W(--bucket #{c.bucket} --output json)
    if c.archives_directory
      list_args += %W(--prefix #{c.archives_directory})
    end
    output = capture_aws_s3api('list-objects', list_args)
    return if output.empty?

    objects = JSON.parse(output)['Contents']
    sorted  = objects.sort_by { |obj| Time.parse(obj['LastModified']) }
    c.s3_keep_releases.times do
      break if sorted.empty?
      sorted.pop
    end
    sorted.each do |obj|
      delete_args = %W(--bucket #{c.bucket} --key #{obj['Key']})
      execute_aws_s3api('delete-object', *delete_args)
    end
  end

  private

  def execute_aws_s3(cmd, *args)
    c = config
    run_locally do
      with(c.aws_environments) do
        execute :aws, 's3', cmd, *args
      end
    end
  end

  def capture_aws_s3(cmd, *args)
    c = config
    run_locally do
      with(c.aws_environments) do
        capture :aws, 's3', cmd, *args
      end
    end
  end

  def execute_aws_s3api(cmd, *args)
    c = config
    run_locally do
      with(c.aws_environments) do
        execute :aws, 's3api', cmd, *args
      end
    end
  end

  def capture_aws_s3api(cmd, *args)
    c = config
    run_locally do
      with(c.aws_environments) do
        capture :aws, 's3api', cmd, *args
      end
    end
  end
end
