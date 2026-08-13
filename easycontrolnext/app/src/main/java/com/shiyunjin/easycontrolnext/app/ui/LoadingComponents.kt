package com.shiyunjin.easycontrolnext.app.ui

import android.app.Dialog
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ContainedLoadingIndicator
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.LoadingIndicatorDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import com.shiyunjin.easycontrolnext.app.ui.theme.EasyControlTheme

/** M3 Loading Indicator default size (guidelines: 48dp, range 24–240dp). */
private val DefaultLoadingIndicatorSize = 48.dp
private val MinLoadingIndicatorSize = 24.dp
private val MaxLoadingIndicatorSize = 240.dp

private fun Dp.clampedLoadingSize(): Dp = when {
  this < MinLoadingIndicatorSize -> MinLoadingIndicatorSize
  this > MaxLoadingIndicatorSize -> MaxLoadingIndicatorSize
  else -> this
}

/**
 * Uncontained M3 Loading Indicator — use on surfaces / inline content.
 * Morphing shape sequence (not a CircularProgressIndicator stroke).
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppLoadingIndicator(
  modifier: Modifier = Modifier,
  size: Dp = DefaultLoadingIndicatorSize,
  color: Color = AccentBlue,
) {
  LoadingIndicator(
    modifier = modifier.size(size.clampedLoadingSize()),
    color = color,
  )
}

/**
 * Contained M3 Loading Indicator — use over other content / overlays.
 * Circular container + on-container active indicator colors.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppContainedLoadingIndicator(
  modifier: Modifier = Modifier,
  size: Dp = LoadingIndicatorDefaults.ContainerWidth,
  containerColor: Color = AccentBlue,
  indicatorColor: Color = Color.White,
) {
  ContainedLoadingIndicator(
    modifier = modifier.size(size.clampedLoadingSize()),
    containerColor = containerColor,
    indicatorColor = indicatorColor,
  )
}

/** @deprecated Prefer [AppLoadingIndicator] / [AppContainedLoadingIndicator]. */
@Deprecated(
  message = "Use AppLoadingIndicator (uncontained) or AppContainedLoadingIndicator (overlay)",
  replaceWith = ReplaceWith("AppLoadingIndicator(modifier, size)"),
)
@Composable
fun AppCircularProgressIndicator(
  modifier: Modifier = Modifier,
  size: Dp = DefaultLoadingIndicatorSize,
  strokeWidth: Dp = 3.dp,
) {
  AppLoadingIndicator(modifier = modifier, size = size)
}

/**
 * Overlay / dialog loading: ContainedLoadingIndicator for contrast over dimmed content.
 * Optional label uses M3 bodyMedium / onSurfaceVariant.
 */
@Composable
fun AppLoadingCard(
  message: String? = null,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier.padding(horizontal = 24.dp, vertical = 20.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    AppContainedLoadingIndicator()
    if (!message.isNullOrBlank()) {
      Surface(
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 0.dp,
      ) {
        Text(
          text = message,
          modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

@Composable
fun AppLoadingDialog(
  message: String? = null,
  onDismissRequest: () -> Unit = {},
) {
  Dialog(
    onDismissRequest = onDismissRequest,
    properties = DialogProperties(
      dismissOnBackPress = false,
      dismissOnClickOutside = false,
      usePlatformDefaultWidth = false,
    ),
  ) {
    AppLoadingCard(message = message)
  }
}

/** Inline loading on a surface — uncontained LoadingIndicator. */
@Composable
fun AppInlineLoading(
  message: String? = null,
  modifier: Modifier = Modifier,
  indicatorSize: Dp = 36.dp,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = 20.dp),
    horizontalArrangement = Arrangement.Center,
    verticalAlignment = Alignment.CenterVertically,
  ) {
    AppLoadingIndicator(size = indicatorSize)
    if (!message.isNullOrBlank()) {
      Spacer(modifier = Modifier.width(12.dp))
      Text(
        text = message,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

/**
 * Host ContainedLoadingIndicator inside a View-based AlertDialog.
 *
 * Platform AlertDialog / AlertDialogLayout does not propagate ViewTree owners, and several
 * callers still use plain [android.app.Activity] (not ComponentActivity). A dialog-scoped
 * LifecycleOwner + SavedStateRegistryOwner + ViewModelStoreOwner is attached before setContent
 * so ComposeView does not crash on attach.
 */
fun installM3ContainedLoadingIndicator(composeView: ComposeView, dialog: Dialog) {
  val owner = DialogComposeOwner().also { it.start() }
  fun View.attachComposeOwners() {
    setViewTreeLifecycleOwner(owner)
    setViewTreeSavedStateRegistryOwner(owner)
    setViewTreeViewModelStoreOwner(owner)
  }

  composeView.attachComposeOwners()
  (composeView.parent as? View)?.attachComposeOwners()

  // Window may already exist after AlertDialog.Builder.create(); also re-bind on show
  // because AlertDialog wraps content under AlertDialogLayout / DecorView.
  fun attachWindowOwners() {
    dialog.window?.decorView?.attachComposeOwners()
  }
  attachWindowOwners()

  composeView.setViewCompositionStrategy(
    ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
  )
  composeView.setContent {
    EasyControlTheme {
      AppContainedLoadingIndicator()
    }
  }

  dialog.setOnShowListener {
    attachWindowOwners()
  }
  dialog.setOnDismissListener {
    owner.destroy()
  }
}

/** Minimal ViewTree owners for Compose hosted in a platform Dialog. */
private class DialogComposeOwner :
  LifecycleOwner,
  ViewModelStoreOwner,
  SavedStateRegistryOwner {

  private val lifecycleRegistry = LifecycleRegistry(this)
  private val store = ViewModelStore()
  private val savedStateRegistryController = SavedStateRegistryController.create(this)
  private var started = false

  init {
    savedStateRegistryController.performRestore(null)
  }

  override val lifecycle: Lifecycle
    get() = lifecycleRegistry

  override val viewModelStore: ViewModelStore
    get() = store

  override val savedStateRegistry: SavedStateRegistry
    get() = savedStateRegistryController.savedStateRegistry

  fun start() {
    if (started) return
    started = true
    lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
    lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
    lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
  }

  fun destroy() {
    if (!started) return
    started = false
    if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
      lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
    }
    if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.STARTED)) {
      lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
    }
    if (lifecycleRegistry.currentState.isAtLeast(Lifecycle.State.CREATED)) {
      lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
    }
    store.clear()
  }
}
