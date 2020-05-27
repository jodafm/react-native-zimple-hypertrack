import { EmitterSubscription } from "react-native";

export type HyperTrackComponent = {
  onErrorHyperTrackSubscription: EmitterSubscription;
  onStartHyperTrackSubscription: EmitterSubscription;
  onStopHyperTrackSubscription: EmitterSubscription;
};
