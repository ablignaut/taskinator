require 'spec_helper'

describe Taskinator::Task do

  let(:definition) do
    Module.new() do
      extend Taskinator::Definition
    end
  end

  describe "Base" do

    let(:process) { Class.new(Taskinator::Process).new('name', definition) }
    subject { Class.new(Taskinator::Task).new('name', process) }

    describe "#initialize" do
      it { expect(subject.process).to_not be_nil }
      it { expect(subject.process).to eq(process) }
      it { expect(subject.uuid).to_not be_nil }
      it { expect(subject.name).to_not be_nil }
      it { expect(subject.options).to_not be_nil }
    end

    describe "#<==>" do
      it { expect(subject).to be_a(::Comparable)  }
      it {
        uuid = subject.uuid
        expect(subject == double('test', :uuid => uuid)).to be
      }

      it {
        expect(subject == double('test', :uuid => 'xxx')).to_not be
      }
    end

    describe "#to_s" do
      it { expect(subject.to_s).to match(/#{subject.uuid}/) }
    end

    describe "#current_state" do
      it { expect(subject).to be_a(::Workflow)  }
      it { expect(subject.current_state).to_not be_nil }
      it { expect(subject.current_state.name).to eq(:initial) }
    end

    describe "#can_complete_task?" do
      it {
        expect {
          subject.can_complete_task?
        }.to raise_error(NotImplementedError)
      }
    end

    describe "workflow" do
      describe "#enqueue!" do
        it { expect(subject).to respond_to(:enqueue!) }
        it {
          expect(subject).to receive(:enqueue)
          subject.enqueue!
        }
        it {
          subject.enqueue!
          expect(subject.current_state.name).to eq(:enqueued)
        }
      end

      describe "#start!" do
        it { expect(subject).to respond_to(:start!) }
        it {
          expect(subject).to receive(:start)
          subject.start!
        }
        it {
          subject.start!
          expect(subject.current_state.name).to eq(:processing)
        }
      end

      describe "#complete!" do
        it { expect(subject).to respond_to(:complete!) }
        it {
          expect(subject).to receive(:can_complete_task?) { true }
          expect(subject).to receive(:complete)
          expect(process).to receive(:task_completed).with(subject)
          subject.start!
          subject.complete!
          expect(subject.current_state.name).to eq(:completed)
        }
      end

      describe "#fail!" do
        it { expect(subject).to respond_to(:fail!) }
        it {
          expect(subject).to receive(:fail).with(StandardError)
          subject.start!
          subject.fail!(StandardError)
        }
        it {
          subject.start!
          subject.fail!(StandardError)
          expect(subject.current_state.name).to eq(:failed)
        }
      end

      describe "#paused?" do
        it { expect(subject.paused?).to_not be }
        it {
          process.start!
          process.pause!
          expect(subject.paused?).to be
        }
      end

      describe "#cancelled?" do
        it { expect(subject.cancelled?).to_not be }
        it {
          process.cancel!
          expect(subject.cancelled?).to be
        }
      end
    end

    describe "#next" do
      it { expect(subject).to respond_to(:next) }
      it { expect(subject).to respond_to(:next=) }
    end

    describe "#accept" do
      it { expect(subject).to be_a(Taskinator::Persistence) }

      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Task::Step do
    it_should_behave_like "a task", Taskinator::Task::Step do
      let(:process) { Class.new(Taskinator::Process).new('process', definition) }
      let(:task) { Taskinator::Task.define_step_task('name', process, :method, {:a => 1, :b => 2}) }
    end

    let(:process) { Class.new(Taskinator::Process).new('process', definition) }
    subject { Taskinator::Task.define_step_task('name', process, :method, {:a => 1, :b => 2}) }

    describe "#executor" do
      it { expect(subject.executor).to_not be_nil }
      it { expect(subject.executor).to be_a(definition) }
    end

    describe "#start!" do
      it "invokes executor" do
        expect(subject.executor).to receive(subject.method).with(*subject.args)
        subject.start!
      end

      it "handles failure" do
        allow(subject.executor).to receive(subject.method).with(*subject.args).and_raise(StandardError)
        expect(subject).to receive(:fail!).with(StandardError)
        subject.start!
      end
    end

    describe "#can_complete_task?" do
      it { expect(subject.can_complete_task?).to_not be }
      it {
        allow(subject.executor).to receive(subject.method).with(*subject.args)
        subject.start!
        expect(subject.can_complete_task?).to be
      }
    end

    describe "#accept" do
      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_attribute).with(:method)
        expect(visitor).to receive(:visit_args).with(:args)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Task::SubProcess do
    it_should_behave_like "a task", Taskinator::Task::SubProcess do
      let(:process) { Class.new(Taskinator::Process).new('process', definition) }
      let(:sub_process) { Class.new(Taskinator::Process).new('sub_process', definition) }
      let(:task) { Taskinator::Task.define_sub_process_task('name', process, sub_process) }
    end

    let(:process) { Class.new(Taskinator::Process).new('process', definition) }
    let(:sub_process) { Class.new(Taskinator::Process).new('sub_process', definition) }
    subject { Taskinator::Task.define_sub_process_task('name', process, sub_process) }

    describe "#start!" do
      it "delegates to sub process" do
        expect(sub_process).to receive(:start)
        subject.start!
      end

      it "handles failure" do
        allow(sub_process).to receive(:start!).and_raise(StandardError)
        expect(subject).to receive(:fail!).with(StandardError)
        subject.start!
      end
    end

    describe "#can_complete_task?" do
      it "delegates to sub process" do
        expect(sub_process).to receive(:completed?)
        subject.can_complete_task?
      end
    end

    describe "#accept" do
      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_process_reference).with(:process)
        expect(visitor).to receive(:visit_task_reference).with(:next)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_process).with(:sub_process)

        subject.accept(visitor)
      }
    end
  end

end
