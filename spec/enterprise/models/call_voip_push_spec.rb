require 'rails_helper'

RSpec.describe Call, 'mobile VoIP push hooks' do
  include ActiveJob::TestHelper

  it 'enqueues an incoming push when a ringing inbound call is created' do
    call = nil
    expect { call = create(:call) }.to have_enqueued_job(Voice::VoipPushJob).with(kind_of(Integer), 'incoming')
    expect(call).to be_persisted
  end

  it 'does not push for outgoing calls' do
    expect { create(:call, direction: :outgoing) }.not_to have_enqueued_job(Voice::VoipPushJob)
  end

  it 'enqueues a cancel push when a ringing inbound call stops ringing' do
    call = create(:call)
    expect { call.update!(status: 'in_progress') }.to have_enqueued_job(Voice::VoipPushJob).with(call.id, 'cancel')
  end

  it 'does not enqueue a second cancel once the call is already past ringing' do
    call = create(:call)
    call.update!(status: 'in_progress')
    expect { call.update!(status: 'completed') }.not_to have_enqueued_job(Voice::VoipPushJob)
  end
end
