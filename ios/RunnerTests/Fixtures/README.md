# Portrait analysis fixtures

`portrait-front-cc-by-sa.jpg` is a 498 x 768 derivative of
[`Actress Anna Unterberger.jpg`](https://commons.wikimedia.org/wiki/File:Actress_Anna_Unterberger.jpg),
photographed by Wolfgang Moroder and published under CC BY-SA 3.0.

The reduced derivative is committed only to prove the production iOS local
face-analysis entry point. It must not be presented as a formal aesthetic
review sample or bundled into the application target.

- Source retrieved: 2026-08-05
- Source license: <https://creativecommons.org/licenses/by-sa/3.0/>
- Derivative SHA-256: `f57d7bdb6ae02759571a1f9c4b5df99b4b88c2f24978fafc3e7f61dca887b66c`

`body-standing-cc-by-sa.jpg` is a 500 x 749 derivative of
[`Lucas Oliveira Miranda.jpg`](https://commons.wikimedia.org/wiki/File:Lucas_Oliveira_Miranda.jpg),
created by Wikimedia Commons user Hagataeu and published under CC BY-SA 4.0.

The reduced derivative is committed only to prove the production iOS local
body-applicability entry point on Simulator. Simulator uses a conservative
face-derived torso proxy because its Vision body-pose and person-segmentation
requests are unavailable; physical-device builds still require both Vision
signals. This fixture must not be presented as physical-device or formal
aesthetic-review evidence, or bundled into the application target.

- Source retrieved: 2026-08-06
- Source license: <https://creativecommons.org/licenses/by-sa/4.0/>
- Derivative SHA-256: `2dad73182ac2febcfd46d73d502bc87cbb7ad25737b0347a7cab9ae784330d6e`

`body-standing-unoccluded-pd.jpg` is a 500 x 752 sRGB derivative of
[`Man-standing.jpg`](https://commons.wikimedia.org/wiki/File:Man-standing.jpg),
self-published by Wikimedia Commons user CharlieCLC into the public domain.
The unobstructed shoulder-to-hip silhouette is used with the production iOS
file renderer to prove that the maximum-safe body control narrows the final
JPEG torso contour by the MVP-required `2%...6%`. It is engineering evidence,
not a claim of physical-device quality or formal reviewer preference, and is
not bundled into the application target.

- Source retrieved: 2026-08-06
- Source license: public domain (`PD-self`)
- Derivative SHA-256: `8e1e4933ea09c54316a8326816f723a03377ac020045f5a85f134d4f7e9c5469`
