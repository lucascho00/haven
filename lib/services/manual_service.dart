import '../models/app_location.dart';
import '../models/manual_item.dart';

class ManualService {
  List<ManualItem> manualsFor(AppLocation? location) {
    final locationName = location?.label ?? 'your area';
    return [
      ManualItem(
        id: 'airstrike-shelter',
        title: 'Airstrike or Explosion Nearby',
        category: 'War',
        summary:
            'Immediate actions when blasts, drones, shelling, or sirens are near $locationName.',
        priority: 1,
        steps: const [
          'Move away from windows and exterior walls immediately.',
          'Go to the lowest interior room, basement, tunnel, or reinforced shelter.',
          'Lie flat, cover your head and neck, and keep your mouth slightly open during blasts.',
          'Do not leave shelter right after the first explosion; wait for a quiet period.',
          'Avoid damaged buildings, dangling wires, gas smell, and unexploded ordnance.',
        ],
      ),
      ManualItem(
        id: 'evacuation-route',
        title: 'Evacuation Decision Checklist',
        category: 'Evacuation',
        summary:
            'Use this before moving through unsafe streets or toward a posted safe place.',
        priority: 2,
        steps: const [
          'Check current route status from cached safe places and local reports.',
          'Bring ID, water, medicine, power bank, cash, warm layers, and first-aid items.',
          'Tell a trusted person your route and expected arrival time if communication works.',
          'Move during daylight when possible and avoid crowds near military targets.',
          'If fighting intensifies, stop at the nearest solid shelter rather than continuing blindly.',
        ],
      ),
      ManualItem(
        id: 'bleeding-trauma',
        title: 'Severe Bleeding First Aid',
        category: 'Medical',
        summary:
            'Life-saving steps for heavy bleeding before professional care arrives.',
        priority: 3,
        steps: const [
          'Apply firm direct pressure with cloth, gauze, or clothing.',
          'If blood soaks through, add more material; do not remove the first layer.',
          'For limb bleeding that will not stop, apply a tourniquet 5-7 cm above the wound.',
          'Write down the tourniquet time and keep the person warm and still.',
          'Seek the nearest cached hospital or clinic route when movement is safer.',
        ],
      ),
      ManualItem(
        id: 'chemical-smoke',
        title: 'Chemical, Smoke, or Gas Exposure',
        category: 'Hazard',
        summary:
            'Reduce exposure if there is unknown gas, smoke, or chemical odor.',
        priority: 4,
        steps: const [
          'Move uphill and upwind if outdoors; avoid low areas where gas can collect.',
          'Cover nose and mouth with layered cloth if no respirator is available.',
          'Remove contaminated outer clothing and seal it away from people.',
          'Rinse exposed skin and eyes with clean water; do not scrub harshly.',
          'Shelter indoors if outside air is unsafe: close windows, vents, and doors.',
        ],
      ),
      ManualItem(
        id: 'earthquake',
        title: 'Earthquake or Building Collapse',
        category: 'Natural Disaster',
        summary: 'Immediate action during shaking or collapse risk.',
        priority: 5,
        steps: const [
          'Drop, cover, and hold under sturdy furniture or beside an interior wall.',
          'Stay away from glass, shelves, heavy furniture, and exterior walls.',
          'After shaking stops, leave damaged buildings carefully and avoid elevators.',
          'If trapped, cover your mouth, tap on pipes/walls, and avoid wasting voice.',
          'Expect aftershocks and move to open ground when safe.',
        ],
      ),
      ManualItem(
        id: 'flood',
        title: 'Flood or Storm Surge',
        category: 'Natural Disaster',
        summary:
            'Avoid drowning, electrocution, and contaminated water exposure.',
        priority: 6,
        steps: const [
          'Move to higher ground immediately; do not wait for official evacuation if water rises.',
          'Never walk or drive through moving floodwater.',
          'Avoid downed power lines and flooded electrical rooms.',
          'Keep drinking water sealed; floodwater may contain sewage, fuel, or chemicals.',
          'Use cached routes only if they avoid bridges, tunnels, and low roads.',
        ],
      ),
    ];
  }
}
