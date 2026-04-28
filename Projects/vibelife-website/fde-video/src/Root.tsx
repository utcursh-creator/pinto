import { Composition } from "remotion";
import { FDEExplainer } from "./FDEExplainer";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="FDEExplainer"
        component={FDEExplainer}
        durationInFrames={30 * 45}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
