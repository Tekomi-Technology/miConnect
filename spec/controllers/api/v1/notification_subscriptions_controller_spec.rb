require 'rails_helper'

RSpec.describe 'Notifications Subscriptions API', type: :request do
  let(:account) { create(:account) }

  describe 'POST /api/v1/notification_subscriptions' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post '/api/v1/notification_subscriptions'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'creates a notification subscriptions' do
        post '/api/v1/notification_subscriptions',
             params: {
               notification_subscription: {
                 subscription_type: 'browser_push',
                 'subscription_attributes': {
                   endpoint: 'test',
                   p256dh: 'test',
                   auth: 'test'
                 }
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['subscription_type']).to eq('browser_push')
        expect(json_response['subscription_attributes']['auth']).to eq('test')
      end

      it 'accepts an apns_voip subscription without overwriting the fcm subscription of the same device' do
        fcm = create(:notification_subscription, user: agent, subscription_type: 'fcm', identifier: 'device-1',
                                                 subscription_attributes: { 'push_token' => 'fcm-token', 'device_id' => 'device-1' })

        post '/api/v1/notification_subscriptions',
             params: {
               notification_subscription: {
                 subscription_type: 'apns_voip',
                 subscription_attributes: { devicePlatform: 'iOS', push_token: 'voip-token', device_id: 'device-1' }
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['subscription_type']).to eq('apns_voip')
        expect(json_response['id']).not_to eq(fcm.id)
        expect(fcm.reload.subscription_type).to eq('fcm')
        expect(fcm.subscription_attributes['push_token']).to eq('fcm-token')
      end

      it 'updates the same apns_voip subscription when the device registers again' do
        2.times do |i|
          post '/api/v1/notification_subscriptions',
               params: {
                 notification_subscription: {
                   subscription_type: 'apns_voip',
                   subscription_attributes: { devicePlatform: 'iOS', push_token: "voip-token-#{i}", device_id: 'device-2' }
                 }
               },
               headers: agent.create_new_auth_token,
               as: :json
          expect(response).to have_http_status(:success)
        end

        expect(agent.notification_subscriptions.where(subscription_type: 'apns_voip').count).to eq(1)
        expect(agent.notification_subscriptions.apns_voip.first.subscription_attributes['push_token']).to eq('voip-token-1')
      end

      it 'returns existing notification subscription if subscription exists' do
        subscription = create(:notification_subscription, user: agent)
        post '/api/v1/notification_subscriptions',
             params: {
               notification_subscription: {
                 subscription_type: 'browser_push',
                 'subscription_attributes': {
                   endpoint: 'test',
                   p256dh: 'test',
                   auth: 'test'
                 }
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['id']).to eq(subscription.id)
      end

      it 'move notification subscription to user if its of another user' do
        subscription = create(:notification_subscription, user: create(:user))
        post '/api/v1/notification_subscriptions',
             params: {
               notification_subscription: {
                 subscription_type: 'browser_push',
                 'subscription_attributes': {
                   endpoint: 'test',
                   p256dh: 'test',
                   auth: 'test'
                 }
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['id']).to eq(subscription.id)
        expect(json_response['user_id']).to eq(agent.id)
      end
    end
  end

  describe 'DELETE /api/v1/notification_subscriptions' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete '/api/v1/notification_subscriptions'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'delete existing notification subscription if subscription exists' do
        subscription = create(:notification_subscription, subscription_type: 'fcm', subscription_attributes: { push_token: 'bUvZo8AYGGmCMr' },
                                                          user: agent)
        delete '/api/v1/notification_subscriptions',
               params: {
                 push_token: subscription.subscription_attributes['push_token']
               },
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect { subscription.reload }.to raise_exception(ActiveRecord::RecordNotFound)
      end

      it 'does not delete another user notification subscription with the same push token' do
        victim = create(:user, account: account, role: :agent)
        victim_subscription = create(:notification_subscription, subscription_type: 'fcm',
                                                                 subscription_attributes: { push_token: 'victimToken' },
                                                                 user: victim)

        delete '/api/v1/notification_subscriptions',
               params: { push_token: 'victimToken' },
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect { victim_subscription.reload }.not_to raise_error
      end
    end
  end
end
