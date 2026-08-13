package com.shiyunjin.easycontrolnext.app.ui

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.navigation.NavBackStackEntry

/**
 * Light page transitions for in-process NavHost (home ↔ settings).
 * Avoids Navigation Compose defaults (~700ms fade+slide) which feel stuttery on OEM devices
 * when composing a new destination on the first frame.
 */
object NavTransitions {
  private const val DURATION_MS = 220

  fun enter(): EnterTransition =
    fadeIn(animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing)) +
      slideInHorizontally(
        animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing),
        initialOffsetX = { fullWidth -> fullWidth / 20 },
      )

  fun exit(): ExitTransition =
    fadeOut(animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing))

  fun popEnter(): EnterTransition =
    fadeIn(animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing))

  fun popExit(): ExitTransition =
    fadeOut(animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing)) +
      slideOutHorizontally(
        animationSpec = tween(DURATION_MS, easing = FastOutSlowInEasing),
        targetOffsetX = { fullWidth -> fullWidth / 20 },
      )

  val enterLambda:
    AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = { enter() }
  val exitLambda:
    AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = { exit() }
  val popEnterLambda:
    AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = { popEnter() }
  val popExitLambda:
    AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = { popExit() }
}
