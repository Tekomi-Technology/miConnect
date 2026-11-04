import { ref } from 'vue';

const analysisVersion = ref(0);
const requestedConversationId = ref(null);

export function useConversationAnalysis() {
  const markAnalyzed = () => {
    analysisVersion.value += 1;
  };

  const requestAnalysis = conversationId => {
    requestedConversationId.value = conversationId;
  };

  const clearRequest = () => {
    requestedConversationId.value = null;
  };

  return {
    analysisVersion,
    markAnalyzed,
    requestedConversationId,
    requestAnalysis,
    clearRequest,
  };
}
