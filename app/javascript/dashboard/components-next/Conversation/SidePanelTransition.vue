<script setup>
// Enter and leave share one duration and easing so that when one side panel
// replaces another the two widths always add up to a single panel width and
// the conversation area beside them stays still.
const SLIDE_CLASSES =
  'transition-[width,min-width,opacity,transform] duration-200 ease-out motion-reduce:transition-none';
const COLLAPSED_CLASSES =
  'opacity-0 ltr:translate-x-full rtl:-translate-x-full xl:!translate-x-0 xl:!w-0 xl:!min-w-0';
</script>

<template>
  <Transition
    :enter-active-class="SLIDE_CLASSES"
    :leave-active-class="SLIDE_CLASSES"
    :enter-from-class="COLLAPSED_CLASSES"
    :leave-to-class="COLLAPSED_CLASSES"
  >
    <slot />
  </Transition>
</template>
