# <img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/Icon.png" width="64" height="64"> Godot Instance Dock
Addon for Godot that adds a handy dock where you can store scenes.

![](https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/Screenshot1.png)

## Cool stuff

The scenes are organized into custom tabs. You can add a scene to the dock using drag and drop and then you can drag it onto your scene, as if dragging the scene file:

<img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeDragAndDrop.gif" width="450">

You can also assign using the Quick Load menu:

<img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeQuickLoad.gif" width="450">

You can use drag and drop within the dock too to rearrage the scenes. When you fill a row, a new row will appear automatically:

<img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeRow.gif" width="245">

Every scene slot has a right-click menu:

![](https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeMenu.png)

- Open Scene: Opens the scene in editor.
- Remove: Removes the scene from slot.
- Refresh Icon: Forces the scene icon to refresh. The icons are cached, so if you edit a scene, you need to refresh the preview.

You can also assign a custom icon to the scene:

<img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeCustom.gif" width="150">

The icons are generated from scenes. They only support 2D and aren't always 100% accurate. so this option is sometimes useful. Scenes with custom icons have a slight outline.

## Technical stuff

The scene list is stored inside your `project.godot` file. Whenever you modify it, your project settings are saved.

The plugin uses Viewport node to generate the scene icon. It just instances the scene inside viewport and saves the rendered texture. If the scene has Node2D root, it will be positioned at half of the preview size.
The default preview size is 64x64. It can be changed in `InstanceDock.gd`. Keep in mind that this is only viewport size. The final texture is resized to the slot size (64x64).

A tab will load when first visible. Due to Viewports requiring a delay to update the texture, generating icons for many scenes takes a couple of seconds. A loading icon will be displayed while the preview is loading.

<img src="https://github.com/KoBeWi/Godot-Instance-Dock/blob/master/Media/ReadmeLoading.gif" width="190">

If the rendered image comes fully transparent, a special icon will be displayed as placeholder.

After first load, the image will be cached in ".godot/InstanceIconCache" folder, so subsequent loads are much faster.

___
You can find all my addons on my [profile page](https://github.com/KoBeWi).

<a href='https://ko-fi.com/W7W7AD4W4' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
