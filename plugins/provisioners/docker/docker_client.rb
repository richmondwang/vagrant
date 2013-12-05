require 'digest/sha1'

module VagrantPlugins
  module Docker
    class DockerClient
      def initialize(machine)
        @machine = machine
      end

      def pull_images(*images)
        @machine.communicate.tap do |comm|
          images.each do |image|
            @machine.ui.info(I18n.t("vagrant.docker_pulling_single", name: image))
            comm.sudo("docker images | grep -q #{image} || docker pull #{image}")
          end
        end
      end

      def start_service
        if !daemon_running? && @machine.guest.capability?(:docker_start_service)
          @machine.guest.capability(:docker_start_service)
        end
      end

      def daemon_running?
        @machine.communicate.test('test -f /var/run/docker.pid')
      end

      def run(containers)
        containers.each do |name, config|
          cids_dir = "/var/lib/vagrant/cids"
          config[:cidfile] ||= "#{cids_dir}/#{Digest::SHA1.hexdigest name}"

          @machine.ui.info(I18n.t("vagrant.docker_running", name: name))
          @machine.communicate.sudo("mkdir -p #{cids_dir}")
          run_container({
            name: name
          }.merge(config))
        end
      end

      def run_container(config)
        raise "Container's cidfile was not provided!" if !config[:cidfile]

        id = "$(cat #{config[:cidfile]})"

        if container_exists?(id)
          start_container(id)
        else
          create_container(config)
        end
      end

      def container_exists?(id)
        @machine.communicate.tap do |comm|
          # Docker < 0.7.0 stores container IDs using its short version while
          # recent versions use the full container ID
          # See https://github.com/dotcloud/docker/pull/2140 for more information
          return comm.test("sudo docker ps -a -q | grep -wFq #{id}") ||
                   comm.test("sudo docker ps -a -q -notrunc | grep -wFq #{id}")
        end
      end

      def start_container(id)
        if !container_running?(id)
          @machine.communicate.sudo("docker start #{id}")
        end
      end

      def container_running?(id)
        @machine.communicate.tap do |comm|
          # Docker < 0.7.0 stores container IDs using its short version while
          # recent versions use the full container ID
          # See https://github.com/dotcloud/docker/pull/2140 for more information
          return comm.test("sudo docker ps -q | grep -wFq #{id}") ||
                   comm.test("sudo docker ps -q -notrunc | grep -wFq #{id}")
        end
      end

      def create_container(config)
        args = "-cidfile=#{config[:cidfile]} -d "
        args << config[:args] if config[:args]
        @machine.communicate.sudo %[
          rm -f #{config[:cidfile]}
          docker run #{args} #{config[:image]} #{config[:cmd]}
        ]
      end
    end
  end
end
