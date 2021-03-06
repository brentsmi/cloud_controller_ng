# Copyright (c) 2009-2012 VMware, Inc.

require File.expand_path("../spec_helper", __FILE__)
require "cloud_controller/health_manager_respondent"

module VCAP::CloudController
  describe HealthManagerRespondent do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:dea_client) { double("dea client", :message_bus => message_bus) }

    let(:droplet) { app.guid }
    let(:indices) { [2] }
    let(:version) { app.version }
    let(:running) { {} }
    let(:instances) { [] }

    let(:payload) do
      { :droplet => droplet,
        :indices => indices,
        :version => version,
        :running => symbolize_keys(running), # ensure we handle this case
        :instances => instances # used for stop requests
      }
    end

    def symbolize_keys(hash)
      hash.inject({}) do |h, (k, v)|
        h[k.to_sym] = v
        h
      end
    end

    subject { HealthManagerRespondent.new(dea_client, message_bus) }

    before do
      dea_client.stub(:stop_instances)
      dea_client.stub(:stop)
      dea_client.stub(:start_instances_with_message)
    end

    describe "#handle_requests" do
      before { message_bus.stub(:subscribe) }

      it "subscribes health.stop and sets up callback to process_stop" do
        message_bus.should_receive(:subscribe).with("health.stop", :queue => "cc") do |&callback|
          callback.call("some payload")
        end

        subject.should_receive(:process_stop).with("some payload")

        subject.handle_requests
      end

      it "subscribes health.start and sets up callback to process_start" do
        message_bus.should_receive(:subscribe).with("health.start", :queue => "cc") do |&callback|
          callback.call("some payload")
        end

        subject.should_receive(:process_start).with("some payload")

        subject.handle_requests
      end
    end

    describe "#process_start" do
      context "when the app does not exist" do
        let(:droplet) { "some-bogus-app-guid" }
        let(:version) { "some-version" }

        it "ignores the request" do
          dea_client.should_not_receive(:start_instances_with_message)

          subject.process_start(payload)
        end
      end

      context "when the app is NOT started" do
        let(:app) do
          Models::App.make :version => "some-version", :instances => 2,
                           :state => "STOPPED"
        end

        it "ignores the request" do
          dea_client.should_not_receive(:start_instances_with_message)

          subject.process_start(payload)
        end
      end

      context "when running instances of current version is < desired instances" do
        let(:app) do
          Models::App.make :version => "some-version", :instances => 2,
                           :state => "STARTED", :package_hash => "abcd"
        end

        let(:running) { { "some-version" => 1 } }

        context "and the version requested to start is current" do
          it "starts the instance" do
            dea_client.should_receive(:start_instances_with_message).with(app, [2])

            subject.process_start(payload)
          end
        end

        context "and the version requested to start is NOT current" do
          let(:version) { "some-bogus-version" }
          it "ignores the request" do
            dea_client.should_not_receive(:start_instances_with_message)

            subject.process_start(payload)
          end
        end
      end

      context "when running instances of current version is >= desired instances" do
        let(:app) do
          Models::App.make :version => "some-version", :instances => 2,
                           :state => "STARTED", :package_hash => "abcd"
        end

        let(:running) { { "some-version" => 2 } }

        it "ignores the request" do
          dea_client.should_not_receive(:start_instances_with_message)

          subject.process_start(payload)
        end
      end
    end

    describe "#process_stop" do
      let(:app) do
        Models::App.make :version => "some-version", :instances => 2,
                         :state => "STARTED", :package_hash => "abcd"
      end

      context "when the app does not exist" do
        let(:droplet) { "some-bogus-app-guid" }

        it "stops the instance" do
          dea_client.should_receive(:stop) do |app|
            expect(app.guid).to eq("some-bogus-app-guid")
          end

          subject.process_stop(payload)
        end
      end

      context "when stopping this instance leaves us with at least the desired number of instances" do
        let(:instances) { { "some-instance" => "some-version" } }
        let(:running) { { "some-version" => 3 } }

        it "stops the instance" do
          dea_client.should_receive(:stop_instances).with(app, ["some-instance"])
          subject.process_stop(payload)
        end
      end

      context "when stopping this instance would leave us with below the desired number of instances" do
        let(:instances) { { "some-instance" => "some-version", "some-other-instance" => "some-version" } }
        let(:running) { { "some-version" => 2 } }

        it "ignores the request" do
          dea_client.should_not_receive(:stop_instances)
          dea_client.should_not_receive(:stop)
          subject.process_stop(payload)
        end
      end

      context "when stopping all of the requested instances would leave us with below the desired number of instances" do
        let(:instances) { { "some-instance" => "some-version", "some-other-instance" => "some-version" } }
        let(:running) { { "some-version" => 3 } }

        it "ignores the request" do
          dea_client.should_not_receive(:stop_instances)
          dea_client.should_not_receive(:stop)
          subject.process_stop(payload)
        end
      end

      context "when the requested version is not current" do
        let(:instances) { { "some-instance" => "some-bogus-version" } }

        context "and there are running instances the current version" do
          let(:running) { { "some-version" => 2 } }

          it "stops the requested (non-current) instance" do
            dea_client.should_receive(:stop_instances).with(app, ["some-instance"])
            subject.process_stop(payload)
          end
        end

        context "and there are NO running instances of the current version" do
          let(:running) { { "some-version" => 0 } }

          it "ignores the request" do
            dea_client.should_not_receive(:stop_instances)
            subject.process_stop(payload)
          end
        end
      end
    end
  end
end
