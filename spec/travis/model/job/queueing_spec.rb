require 'spec_helper'

describe Job::Queueing do
  include Travis::Testing::Stubs

  let(:queueing) { Job::Queueing.new(test) }
  let(:queue)    { stub('queue', :publish => true) }

  before :each do
    Travis::Amqp::Publisher.stubs(:builds).returns(queue)
    Travis::Api.stubs(:data).returns({})
    test.stubs(:enqueue)
  end

  describe 'if the job is enqueueable' do
    before :each do
      Job::Limit.stubs(:enqueueable?).with(test).returns(true)
    end

    it 'enqueues the job' do
      test.expects(:enqueue)
      queueing.run
    end

    it 'publishes an amqp message' do
      queue.expects(:publish)
      queueing.run
    end

    it 'publishes on the job queue' do
      Travis::Amqp::Publisher.expects(:builds).with('builds.common').returns(queue)
      queueing.run
    end

    it 'publishes a worker payload' do
      Travis::Api.expects(:data).with(test, :for => 'worker', :type => 'Job::Test', :version => 'v0')
      queueing.run
    end
  end

  describe 'if the job is not enqueueable' do
    before :each do
      Job::Limit.stubs(:enqueueable?).with(test).returns(false)
    end

    it 'does not enqueue the job' do
      test.expects(:enqueue).never
      queueing.run
    end

    it 'does not publish an amqp message' do
      queue.expects(:publish).never
      queueing.run
    end
  end
end

describe Job::Queueing::All do
  include Travis::Testing::Stubs
  include Support::ActiveRecord

  it 'tries to enqueue each queueable job' do
    Job.stubs(:queueable).returns [test, test]
    Job::Queueing.any_instance.expects(:run).twice
    Job::Queueing::All.new.run
  end

  describe 'queueing order' do
    let(:config)    { { :rvm => ['1.9.3', 'rbx', 'jruby'] } }
    let!(:builds)   { [Factory(:build, :config => config), Factory(:build, :config => config), Factory(:build, :config => config)] }
    let(:publisher) { Support::Mocks::Amqp::Publisher.new }

    before :each do
      Travis::Amqp::Publisher.stubs(:builds).returns(publisher)
    end

    it 'enqueues jobs in the expected order' do
      Job::Queueing::All.new.run
      expected = Job.order(:id).map(&:id)[0, 5]
      actual = publisher.messages.map { |message| message.first['job']['id'] }
      actual.should == expected
    end
  end
end
