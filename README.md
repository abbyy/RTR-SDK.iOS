
# Samples for ABBYY Mobile Capture for iOS

This folder contains code samples for ABBYY Mobile Capture for iOS.



## About ABBYY Mobile Capture

Mobile Capture is a Software Development Kit (SDK), which allows automatic capture of an image, by simply pointing the camera on the document, for further back end processes or recognition of the data from the document in real time on the mobile device requiring minimal interaction from the user.

The samples cover the following scenarios:

- Text capture (**sample-textcapture**, **sample-textcapture-swift**)

  The basic usage scenario. The user simply points their camera at the text, which is then recognized and displayed or saved in memory.

- Data capture (**sample-datacapture**, **sample-datacapture-swift**)

  Custom data field capture: only the data that matches the specified regular expression will be extracted.

- Core API (**sample-coreapi**, **sample-coreapi-swift**)

  The sample demonstrates the core API usage in a simple scenario of capturing data from an image.

- Image capture (**sample-imagecapture**, **sample-imagecapture-swift**)

  This simple image capture scenarios demonstrate how to automatically capture an image from the smartphone video preview frames.

- Single-page image capture with UI (**sample-ui-imagecapture**, **sample-ui-imagecapture-swift**)

  This sample illustrates the steps you need to perform to create a simple mobile application for image capture.
  
- Multipage image capture with UI **sample-ui-imagecapture-multipage**, **sample-ui-imagecapture-multipage-swift**)

  The sample code implementing a multipage image capture scenario with tuned user interface.

## Prerequisites

To try out the real-time OCR technology using these samples, request ABBYY Mobile Capture trial version on the [ABBYY website](http://www.abbyy.com/mobile-capture-sdk/#request-demo). 

In the download package you will find:

- the library itself (**libs/AbbyyRtrSDK.framework** and all modules from the libs folder)
- resource files:
  - **assets/dictionaries** — dictionary support for some of the recognition languages; using a dictionary improves the result quality
  - **assets/patterns** — recognition databases

**Note:** You are **not allowed** to include assets or license in any branch of this sample in public repositories. This notice must be included in all public branches. Anyone wishing to try out the samples should request their own copy of the library from the above link and use the assets from that copy.


## Building the samples

Please change the bundle ID before building, modifying or otherwise using any of the samples.

The samples should be open and built from the same folder where they are located in the distribution package. All samples work out of the box.