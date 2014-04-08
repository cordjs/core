CordJS
====
CordJS is a framework to build web-based frontend applications. Unlike many other frameworks it's not aimed to be a lightweight. The purpose is to create a full-stack framework that let the developer build real-world big applications without having to deal with lots of boilerplate and difficult decisions.

CordJS most likely conforms to MVVM pattern. The framework is heavily view-centric (view-first). It's implied that most of heavy business-logic is processed on some backend written using some another framework and communicated via REST API. 

Main properties are:
* Written in CoffeeScript.
* The main building block is widget. Everything displayed on the page are widgets. Pages are widgets, layouts are widgets, controls are widgets. Widgets are organized in hierarchy with the root widget representing the current page.
* Pages can be rendered on browser and server similarly without code duplication. Refresh button pressing will not reset the view to the original default page.
* Browser history API is heavily used. Old browsers are not supported.
* AMD module/dependency resolving system is used with requirejs.
* Threre is a strict code layout with bundles system (inspired by Symfony's bundles) to organize application modules.
* Template engine is text-based (not DOM-based). Now dustjs is used with some framework-specific plugins. (May be subject to change to provide angular-style smart auto-updating of the widget's DOM-representations.
* DI is included.
* Models and collections subsystem is included.
* REST-API client with OAuth 2.0 authentication support is included.
* Has it's own build tool with smart assets optimizer.

One of the main features of the framework is that initial page (view) is rendered on the server-side (node.js), which is very web-frendly (search-engines will like this) and allows to show the full page to the user at ones, not "loading..." message. This is one of the main reasons why this frameworks was born.

CordJS is still under heavy development. There are no any unit-test or documentation. It's planned to be more public-available in mid-2014.

CordJS is developed for the real-life commecial project -- new fully rewritten version of the megaplan.ru (one of the leading russian SaaS task manager and CRM for SMB). So this is not just an academic research.

Available under terms of MIT license &copy; Megaplan LLC.
