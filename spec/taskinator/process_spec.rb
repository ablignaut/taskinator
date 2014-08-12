require 'spec_helper'

describe Taskinator::Process do

  let(:definition) do
    Module.new() do
      extend Taskinator::Definition
    end
  end

  describe "Base" do

    subject { Class.new(Taskinator::Process).new('name', definition) }

    describe "#initialize" do
      it { expect(subject.uuid).to_not be_nil }
      it { expect(subject.name).to_not be_nil }
      it { expect(subject.definition).to_not be_nil }
      it { expect(subject.definition).to eq(definition) }
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

    describe "#tasks" do
      it { expect(subject.tasks).to be_a(Taskinator::Tasks) }
    end

    describe "#to_s" do
      it { expect(subject.to_s).to match(/#{subject.uuid}/) }
    end

    describe "#current_state" do
      it { expect(subject).to be_a(::Workflow)  }
      it { expect(subject.current_state).to_not be_nil }
      it { expect(subject.current_state.name).to eq(:initial) }
    end

    describe "#tasks_completed?" do
      it {
        expect {
          subject.tasks_completed?
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

      describe "#cancel!" do
        it { expect(subject).to respond_to(:cancel!) }
        it {
          expect(subject).to receive(:cancel)
          subject.cancel!
        }
        it {
          subject.cancel!
          expect(subject.current_state.name).to eq(:cancelled)
        }
      end

      describe "#pause!" do
        it { expect(subject).to respond_to(:pause!) }
        it {
          expect(subject).to receive(:pause)
          subject.start!
          subject.pause!
        }
        it {
          subject.start!
          subject.pause!
          expect(subject.current_state.name).to eq(:paused)
        }
      end

      describe "#resume!" do
        it { expect(subject).to respond_to(:resume!) }
        it {
          expect(subject).to receive(:resume)
          subject.start!
          subject.pause!
          subject.resume!
        }
        it {
          subject.start!
          subject.pause!
          subject.resume!
          expect(subject.current_state.name).to eq(:processing)
        }
      end

      describe "#complete!" do
        it { expect(subject).to respond_to(:complete!) }
        it {
          allow(subject).to receive(:tasks_completed?) { true }
          expect(subject).to receive(:complete)
          subject.start!
          subject.complete!
        }
        it {
          expect(subject).to receive(:tasks_completed?) { true }
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
    end

    describe "#parent" do
      it "notifies parent" do
        allow(subject).to receive(:tasks_completed?) { true }
        subject.parent = double('parent')
        expect(subject.parent).to receive(:complete!)
        subject.start!
        subject.complete!
      end
    end

    describe "persistence" do
      it { expect(subject).to be_a(Taskinator::Persistence) }

      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_task_reference).with(:parent)
        expect(visitor).to receive(:visit_tasks)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Process::Sequential do

    it_should_behave_like "a process", Taskinator::Process::Sequential do
      let(:process) { Taskinator::Process.define_sequential_process_for('name', definition) }
    end

    subject { Taskinator::Process.define_sequential_process_for('name', definition) }

    let(:tasks) {
      [
        Class.new(Taskinator::Task).new('task1', subject),
        Class.new(Taskinator::Task).new('task2', subject)
      ]
    }

    describe ".define_sequential_process_for" do
      it "raise error for nil definition" do
        expect {
          Taskinator::Process.define_sequential_process_for('name', nil)
        }.to raise_error(ArgumentError)
      end

      it "raise error for invalid definition" do
        expect {
          Taskinator::Process.define_sequential_process_for('name', Object)
        }.to raise_error(ArgumentError)
      end
    end

    describe "#start!" do
      it "executes the first task" do
        tasks.each {|t| subject.tasks << t }
        task1 = tasks[0]

        expect(subject.tasks).to receive(:first).and_call_original
        expect(task1).to receive(:enqueue!)

        subject.start!
      end

      it "completes if no tasks" do
        expect(subject).to receive(:complete!)
        subject.start!
      end
    end

    describe "#task_completed" do
      it "executes the next task" do
        tasks.each {|t| subject.tasks << t }
        task1 = tasks[0]
        task2 = tasks[1]

        expect(task1).to receive(:next).and_call_original
        expect(task2).to receive(:enqueue!)

        subject.task_completed(task1)
      end

      it "completes if no more tasks" do
        tasks.each {|t| subject.tasks << t }
        task2 = tasks[1]

        expect(subject).to receive(:can_complete?) { true }
        expect(subject).to receive(:complete!)

        subject.task_completed(task2)
      end
    end

    describe "#tasks_completed?" do
      it "one or more tasks are incomplete" do
        tasks.each {|t| subject.tasks << t }

        expect(subject.tasks_completed?).to_not be
      end

      it "all tasks are complete" do
        tasks.each {|t|
          subject.tasks << t
          allow(t).to receive(:completed?) { true }
        }

        expect(subject.tasks_completed?).to be
      end
    end

    describe "#accept" do
      it { expect(subject).to be_a(Taskinator::Persistence) }

      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_task_reference).with(:parent)
        expect(visitor).to receive(:visit_tasks)

        subject.accept(visitor)
      }
    end
  end

  describe Taskinator::Process::Concurrent do
    it_should_behave_like "a process", Taskinator::Process::Concurrent do
      let(:process) { Taskinator::Process.define_concurrent_process_for('name', definition, Taskinator::CompleteOn::First) }

      it { expect(process.complete_on).to eq(Taskinator::CompleteOn::First)  }
    end

    subject { Taskinator::Process.define_concurrent_process_for('name', definition) }

    let(:tasks) {
      [
        Class.new(Taskinator::Task).new('task1', subject),
        Class.new(Taskinator::Task).new('task2', subject)
      ]
    }

    describe ".define_concurrent_process_for" do
      it "raise error for nil definition" do
        expect {
          Taskinator::Process.define_concurrent_process_for('name', nil)
        }.to raise_error(ArgumentError)
      end

      it "raise error for invalid definition" do
        expect {
          Taskinator::Process.define_concurrent_process_for('name', Object)
        }.to raise_error(ArgumentError)
      end
    end

    describe "#start!" do
      it "executes all tasks" do
        tasks.each {|t|
          subject.tasks << t
          expect(t).to receive(:enqueue!)
        }

        subject.start!
      end

      it "completes if no tasks" do
        expect(subject).to receive(:complete!)
        subject.start!
      end
    end

    describe "#task_completed" do
      it "completes when tasks complete" do
        tasks.each {|t| subject.tasks << t }

        expect(subject).to receive(:can_complete?) { true }
        expect(subject).to receive(:complete!)

        subject.task_completed(tasks.first)
      end
    end

    describe "#tasks_completed?" do

      describe "complete on first" do
        let(:process) { Taskinator::Process.define_concurrent_process_for('name', definition, Taskinator::CompleteOn::First) }

        it "yields false when no tasks have completed" do
          tasks.each {|t| process.tasks << t }

          expect(process.tasks_completed?).to_not be
        end

        it "yields true when one or more tasks have completed" do
          tasks.each {|t|
            process.tasks << t
            allow(t).to receive(:completed?) { true }
          }

          expect(process.tasks_completed?).to be
        end
      end

      describe "complete on last" do
        let(:process) { Taskinator::Process.define_concurrent_process_for('name', definition, Taskinator::CompleteOn::Last) }

        it "yields false when no tasks have completed" do
          tasks.each {|t| process.tasks << t }

          expect(process.tasks_completed?).to_not be
        end

        it "yields false when one, but not all, tasks have completed" do
          tasks.each {|t| process.tasks << t }
          allow(tasks.first).to receive(:completed?) { true }

          expect(process.tasks_completed?).to_not be
        end

        it "yields true when all tasks have completed" do
          tasks.each {|t|
            process.tasks << t
            allow(t).to receive(:completed?) { true }
          }

          expect(process.tasks_completed?).to be
        end
      end
    end

    describe "#accept" do
      it { expect(subject).to be_a(Taskinator::Persistence) }

      it {
        expect(subject).to receive(:accept)
        subject.save
      }

      it {
        visitor = double('visitor')
        expect(visitor).to receive(:visit_type).with(:definition)
        expect(visitor).to receive(:visit_attribute).with(:uuid)
        expect(visitor).to receive(:visit_attribute).with(:name)
        expect(visitor).to receive(:visit_attribute).with(:complete_on)
        expect(visitor).to receive(:visit_args).with(:options)
        expect(visitor).to receive(:visit_task_reference).with(:parent)
        expect(visitor).to receive(:visit_tasks)

        subject.accept(visitor)
      }
    end
  end

end
