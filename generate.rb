#!/usr/bin/env ruby
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Author: Chris Aumann <me@chr4.org>
#
#
# Note: This script requires the newline patches of Trousseau
# https://github.com/oleiade/trousseau/pull/84/files
#
# Be careful until this is merged!

require 'json'
require 'yaml'
require 'boson/runner'
require 'tempfile'

class GenerateRunner < Boson::Runner
  # Path to trousseau binary
  @@trousseau = 'trousseau'

  YAML::load_file('config.yaml').each do |data_bag_name, config|
    # Add default configuration options, unless already set
    config['trousseau_store'] ||= "./#{data_bag_name}/trousseau.asc"
    config['data_bag_secret'] ||= "/etc/chef/#{data_bag_name}_data_bag_secret"
    config['description'] ||= "Create/Upload encrypted data bag for #{data_bag_name}"

    # Define Boson options
    desc config['description']
    option 'id',     type: :string, desc: 'Data bag id (defaults to item)'
    option 'target', type: :array,  desc: 'Target user@host[,user2@host2] to upload data_bag_secret to'

    # Dynamically create method for each data_bag in config
    define_method(data_bag_name) do |item, options|
      ENV['TROUSSEAU_STORE'] = config['trousseau_store']
      list = %x(#{@@trousseau} keys)

      # Retrieve all requested items from trousseau
      data_bag = populate_hash(config['data_bag'], item)

      if data_bag.empty?
        puts 'No data bag elements found.'
        return
      end

      # Use item as id, unless --id is given, or manually specified in yaml
      data_bag['id'] ||= options['id'] ? options['id'] : item

      # Dots are not valid in a data bag id. Automatically replace them with underscores
      # See: https://github.com/atomic-penguin/cookbook-certificate/pull/38
      data_bag['id'] = data_bag['id'].gsub('.', '_')

      # Generate a data_bag_secret unless it is already present
      generate_data_bag_secret(item) unless list.match /^#{item}\/data_bag_secret/

      # Update/Create encrypted data bag from Trousseau information
      update_data_bag(data_bag_name, item, data_bag)

      # Copy data_bag_secret to target servers
      Array(options['target']).each do |target|
        copy_data_bag_secret(item, target, config['data_bag_secret'])
      end
    end

  end

private

  # Populate a hash with the corresponding trousseau items
  def populate_hash(hash, item)
    res = {}
    hash.each do |key, value|
      # Recursivly process hashes
      if value.is_a?(Hash)
        res[key] = populate_hash(value, item)
      else
        # Replace %s in value string with the current item.
        # Redirect stderr to /dev/null, to prevent "key not found" messages from being displayed
        res[key] = `#{@@trousseau} get #{value % item} 2> /dev/null`.chomp
      end
    end

    # Reject empty keys
    res.reject { |_, v| v.empty? }
  end

  # Generate a data_bag_secret using OpenSSL,
  # store it in Trousseau as "target/data_bag_secret"
  def generate_data_bag_secret(target, length=512)
    secret = %x(openssl rand -base64 #{length}).chomp
    system("#{@@trousseau} set #{target}/data_bag_secret '#{secret}'")
  end

  # Generate a passphrase,
  # store it in trousseau as "target.passphrase"
  def generate_passphrase(target, length=20)
    passphrase = %x(pwgen -n1 50).chomp
    system("#{@@trousseau} set #{target}.passphrase #{passphrase}")
  end

  # Generate JSON from Trousseau information,
  # then encrypt it using the corresponding data_bag_secret
  # and upload data bag to Chef server
  def update_data_bag(data_bag, item, element)
    secret = %x(#{@@trousseau} get #{item}/data_bag_secret).chomp

    # Remove empty keys from hashes
    element.reject! { |_, v| v.empty? } if element.is_a?(Hash)

    # Generate temporary .json file
    tempfile = Tempfile.new(%w(knife-generate .json))
    tempfile.write(JSON.pretty_generate(element))
    tempfile.close

    system("knife data bag from file #{data_bag} #{tempfile.path} --secret '#{secret}'")
  end

  # Copy the data_bag_secret of "item" to the target server
  def copy_data_bag_secret(item, target, file='/etc/chef/encrypted_data_bag_secret')
    secret = %x(#{@@trousseau} get #{item}/data_bag_secret).chomp
    puts "Copying data_bag_secret to #{target}"
    system("ssh #{target} \"echo '#{secret}' |sudo tee #{file} > /dev/null && sudo chmod 00600 #{file} && sudo chown root:root #{file}\"")
  end
end

GenerateRunner.start
